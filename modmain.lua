local ImageButton = require("widgets/imagebutton")
local Text = require("widgets/text")
local UIAnim = require("widgets/uianim")
local UIAnimButton = require("widgets/uianimbutton")
local Widget = require("widgets/widget")
local Templates = require("widgets/redux/templates")
local PersistentData = require("persistentdata")
local Brain = require("turbojimbo_brain")
local AvgStats = require("turbojimbo_stats")
modimport("scripts/strings.lua")

local STRINGS = GLOBAL.STRINGS

--------------------------------------------------------------------------------
-- Smart AI settings (edited in the in-game CONFIGS panel, saved with the mod data)
--------------------------------------------------------------------------------

local GOAL_OPTIONS = {
	{ text = "Balanced", data = "balanced" },
	{ text = "Jackpot", data = "jackpot" },
	{ text = "Safe", data = "safe" },
}
local BUDGET_OPTIONS = {
	{ text = "Fast", data = 0.5 },
	{ text = "Normal", data = 1 },
	{ text = "Deep", data = 2 },
	{ text = "Very deep", data = 4 },
}
-- Auto reroll: reroll before picking a joker if the best joker's expected loot value is below this.
local REROLL_OPTIONS = AvgStats.REROLL_OPTIONS
local MAX_REROLLS_IN_A_ROW = 40

local function OptionText(options, data)
	for _, o in ipairs(options) do
		if o.data == data then return o.text end
	end
	return tostring(data)
end
local function IsOption(options, data)
	for _, o in ipairs(options) do
		if o.data == data then return true end
	end
	return false
end

-- Cooperative multitasking: the solver yields every QUOTA leaf evaluations,
-- and we keep resuming it for at most FRAME_BUDGET seconds per frame.
local QUOTA = 1500
local FRAME_BUDGET = 0.012
local MAX_STEPS_PER_FRAME = 40

local function Now()
	if GLOBAL.os ~= nil and GLOBAL.os.clock ~= nil then
		return GLOBAL.os.clock()
	end
	return nil
end

local configs -- loaded below

local function Utility()
	return Brain.PROFILES[configs.ai.goal] or Brain.PROFILES.balanced
end

local function BrainOpts()
	return { quota = QUOTA, scale = configs.ai.budget }
end

--------------------------------------------------------------------------------
-- Saved data. Other mods can access this with persistentdata.
--------------------------------------------------------------------------------

local DEFAULT_CHECKBOXES = {
	turbo = false,
	replay = false,
	autoplay = false,
	reveal_cards = false,
	macros_end_round = false,
	skip_ending = false,
	smart = true,
	auto_reroll = false,
}

local DEFAULT_JOKERS_RANK = {
	"wendy", "wurt", "webber", "winona", "wilson", "wathgrithr", "waxwell", "walter", "wx78",
	"woodie", "warly", "wormwood", "wortox", "wolfgang", "wickerbottom", "willow", "wes", "wanda",
}

local ModData = PersistentData(modname)
ModData:Load()

configs = ModData:GetValue("configs")
if type(configs) ~= "table" then
	configs = {}
end
if type(configs.checkboxes) ~= "table" then
	configs.checkboxes = {}
end
-- Older saves don't have the new options, fill them in.
for key, value in pairs(DEFAULT_CHECKBOXES) do
	if configs.checkboxes[key] == nil then
		configs.checkboxes[key] = value
	end
end
local function IsValidRank(rank)
	if type(rank) ~= "table" or #rank ~= #DEFAULT_JOKERS_RANK then
		return false
	end
	local seen = {}
	for _, name in ipairs(rank) do
		if seen[name] or Brain.JCODE[name] == nil then
			return false
		end
		seen[name] = true
	end
	return true
end
if not IsValidRank(configs.jokers_rank) then
	configs.jokers_rank = {}
	for i, name in ipairs(DEFAULT_JOKERS_RANK) do
		configs.jokers_rank[i] = name
	end
end
-- Smart AI settings
if type(configs.ai) ~= "table" then
	configs.ai = {}
end
if not IsOption(GOAL_OPTIONS, configs.ai.goal) then configs.ai.goal = "balanced" end
if not IsOption(BUDGET_OPTIONS, configs.ai.budget) then configs.ai.budget = 1 end
if not IsOption(REROLL_OPTIONS, configs.ai.reroll) then configs.ai.reroll = AvgStats.DEFAULT_REROLL end
-- Your own results (reward rank counts + rerolls)
if type(configs.stats) ~= "table" or type(configs.stats.ranks) ~= "table" then
	configs.stats = { ranks = { 0, 0, 0, 0, 0, 0, 0, 0 }, rerolls = 0 }
end
for r = 1, 8 do
	configs.stats.ranks[r] = GLOBAL.tonumber(configs.stats.ranks[r]) or 0
end
configs.stats.rerolls = GLOBAL.tonumber(configs.stats.rerolls) or 0
ModData:SetValue("configs", configs)
ModData:Save()

local function SaveConfigs()
	ModData:SetValue("configs", configs)
	ModData:Save()
end

-- Auto reroll streak, shared between game screens.
local reroll_streak = 0

--------------------------------------------------------------------------------
-- Classic macros (used when Smart AI is off). Same as before, with bug fixes:
-- `round` -> `self.round`, WX-78 now really discards the hearts it kept.
--------------------------------------------------------------------------------

local SUITS = {
	SPADES = 1,
	HEARTS = 2,
	CLUBS = 3,
	DIAMONDS = 4,
}
local macro_tree = {
	joker = {
		[1] = "CHOOSE_JOKER",
		[2] = nil,
	},
	deal = {
		wurt = { [1] = "KEEP_FACES", [2] = nil },
		wortox = { [1] = "KEEP_HEARTS", [2] = "DISCARD_HEARTS" },
		warly = { [1] = nil, [2] = nil },
		winona = { [1] = "KEEP_HEARTS", [2] = nil },
		wes = { [1] = nil, [2] = "DISCARD_ALL" },
		wendy = { [1] = nil, [2] = "DISCARD_ALL" },
		webber = { [1] = "DISCARD_HEARTS_AND_DIAMONDS", [2] = "DISCARD_ALL" },
		woodie = { [1] = nil, [2] = "DISCARD_ALL" },
		wolfgang = { [1] = "KEEP_KINGS", [2] = nil },
		willow = { [1] = nil, [2] = "DISCARD_FACES" },
		wx78 = { [1] = "KEEP_HEARTS", [2] = "DISCARD_HEARTS" },
		wickerbottom = { [1] = "KEEP_QUEENS", [2] = nil },
		waxwell = { [1] = nil, [2] = "DISCARD_HEARTS" },
		walter = { [1] = nil, [2] = "DISCARD_ALL" },
		wormwood = { [1] = "KEEP_CLUBS", [2] = nil },
		wanda = { [1] = nil, [2] = nil },
		wathgrithr = { [1] = "KEEP_SPADES", [2] = nil },
		wilson = { [1] = "KEEP_PAIRS", [2] = nil },
	},
}
local macro_defs = {}
macro_defs.CHOOSE_JOKER = function(self)
	local joker_choices = {}
	for joker_index = 1, 3 do
		joker_choices[self.root["joker_card" .. joker_index].joker_selected.name] = joker_index
	end
	for rank, name in ipairs(configs.jokers_rank) do
		if joker_choices[name] then
			self:SelectJoker(joker_choices[name])
			return
		end
	end
	if self.joker_choice == nil then
		self:SelectJoker(1) -- a joker this mod doesn't know yet
	end
end
local function GroupByNumber(self)
	local seen_numbers = {}
	for card_index = 1, 5 do
		local num = self:Num(card_index)
		seen_numbers[num] = seen_numbers[num] or {}
		table.insert(seen_numbers[num], card_index)
	end
	return seen_numbers
end
macro_defs.SELECT_PAIRS = function(self)
	for _, cards in pairs(GroupByNumber(self)) do
		if #cards > 1 then
			for _, card_index in ipairs(cards) do self:MarkForDiscard(card_index) end
		end
	end
end
macro_defs.SELECT_PAIRS_ABOVE = function(self, threshold)
	for seen_number, cards in pairs(GroupByNumber(self)) do
		if seen_number > threshold and #cards > 1 then
			for _, card_index in ipairs(cards) do self:MarkForDiscard(card_index) end
		end
	end
end
macro_defs.SELECT_SUIT = function(self, suit)
	for card_index = 1, 5 do
		if self:Suit(card_index) == suit then self:MarkForDiscard(card_index) end
	end
end
macro_defs.SELECT_NUM = function(self, num)
	for card_index = 1, 5 do
		if self:Num(card_index) == num then self:MarkForDiscard(card_index) end
	end
end
macro_defs.SELECT_ABOVE = function(self, threshold)
	for card_index = 1, 5 do
		if self:Num(card_index) > threshold then self:MarkForDiscard(card_index) end
	end
end
macro_defs.SELECT_ABOVE_WITH_ACE = function(self, threshold)
	for card_index = 1, 5 do
		local card_num = self:Num(card_index)
		if card_num > threshold or (card_num == 1 and threshold < 11) then
			self:MarkForDiscard(card_index)
		end
	end
end
macro_defs.KEEP_ALL = function(self)
	for card_index = 1, 5 do self:UnmarkForDiscard(card_index) end
end
macro_defs.DISCARD_ALL = function(self)
	for card_index = 1, 5 do self:MarkForDiscard(card_index) end
end
macro_defs.INVERT_SELECTION = function(self)
	for card_index = 1, 5 do
		if self.discard[card_index] then
			self:UnmarkForDiscard(card_index)
		else
			self:MarkForDiscard(card_index)
		end
	end
end
local function KeepWhere(select_fn)
	return function(self, ...)
		macro_defs.KEEP_ALL(self)
		select_fn(self, ...)
		macro_defs.INVERT_SELECTION(self)
	end
end
macro_defs.KEEP_PAIRS = KeepWhere(function(self) macro_defs.SELECT_PAIRS(self) end)
macro_defs.KEEP_HEARTS = KeepWhere(function(self) macro_defs.SELECT_SUIT(self, SUITS.HEARTS) end)
macro_defs.KEEP_CLUBS = KeepWhere(function(self) macro_defs.SELECT_SUIT(self, SUITS.CLUBS) end)
macro_defs.KEEP_SPADES = KeepWhere(function(self) macro_defs.SELECT_SUIT(self, SUITS.SPADES) end)
macro_defs.KEEP_FACES = KeepWhere(function(self) macro_defs.SELECT_ABOVE(self, 10) end)
macro_defs.KEEP_HIGH = KeepWhere(function(self) macro_defs.SELECT_ABOVE_WITH_ACE(self, 7) end)
macro_defs.KEEP_KINGS = KeepWhere(function(self) macro_defs.SELECT_NUM(self, 13) end)
macro_defs.KEEP_QUEENS = KeepWhere(function(self) macro_defs.SELECT_NUM(self, 12) end)
macro_defs.DISCARD_HEARTS = function(self)
	macro_defs.KEEP_ALL(self)
	macro_defs.SELECT_SUIT(self, SUITS.HEARTS)
end
macro_defs.DISCARD_HEARTS_AND_DIAMONDS = function(self)
	macro_defs.KEEP_ALL(self)
	macro_defs.SELECT_SUIT(self, SUITS.HEARTS)
	macro_defs.SELECT_SUIT(self, SUITS.DIAMONDS)
end
macro_defs.DISCARD_FACES = function(self)
	macro_defs.KEEP_ALL(self)
	macro_defs.SELECT_ABOVE(self, 10)
end
local function CountSuit(self, suit)
	local n = 0
	for i = 1, 5 do
		if self:Suit(i) == suit then n = n + 1 end
	end
	return n
end
macro_defs.WURT = KeepWhere(function(self)
	-- J, Q, K only: aces are not face cards for Wurt.
	macro_defs.SELECT_ABOVE(self, 10)
end)
macro_defs.WORTOX = function(self)
	macro_defs.KEEP_ALL(self)
	macro_defs.SELECT_SUIT(self, SUITS.HEARTS)
	macro_defs.INVERT_SELECTION(self)
	macro_defs.SELECT_PAIRS_ABOVE(self, 4)
	macro_defs.INVERT_SELECTION(self)
end
macro_defs.WARLY = function(self)
	macro_defs.KEEP_ALL(self)
	local suit_tally = {}
	for card_index = 1, 5 do
		local suit = self:Suit(card_index)
		local value = self:Num(card_index) == 1 and 11 or self:Num(card_index)
		suit_tally[suit] = suit_tally[suit] or { cards = {}, max_num = 0 }
		table.insert(suit_tally[suit].cards, card_index)
		suit_tally[suit].max_num = math.max(suit_tally[suit].max_num, value)
	end
	for _, suit_data in pairs(suit_tally) do
		for _, card_index in ipairs(suit_data.cards) do
			local card_num = self:Num(card_index)
			if ((card_num == 1 and 11) or card_num) < suit_data.max_num and card_num < 9 then
				self:MarkForDiscard(card_index)
			end
		end
	end
end
macro_defs.WES = function(self)
	macro_defs.KEEP_ALL(self)
	macro_defs.SELECT_ABOVE_WITH_ACE(self, self.round == 1 and 8 or 7)
	macro_defs.SELECT_PAIRS_ABOVE(self, 4)
	macro_defs.INVERT_SELECTION(self)
end
macro_defs.WINONA = function(self)
	if self.round ~= 1 and CountSuit(self, SUITS.HEARTS) + self.mult < 1 then
		macro_defs.DISCARD_HEARTS(self)
		macro_defs.SELECT_ABOVE_WITH_ACE(self, 7)
		macro_defs.SELECT_PAIRS_ABOVE(self, 4)
		macro_defs.INVERT_SELECTION(self)
	else
		macro_defs.DISCARD_HEARTS(self)
		macro_defs.SELECT_ABOVE_WITH_ACE(self, 9)
		macro_defs.INVERT_SELECTION(self)
	end
end
macro_defs.WENDY = function(self)
	if self.round == 1 then
		macro_defs.DISCARD_ALL(self)
	elseif self.mult < 1 then
		macro_defs.WES(self)
	else
		macro_defs.KEEP_HIGH(self)
	end
end
macro_defs.WEBBER = function(self)
	if self.round == 1 then
		macro_defs.KEEP_ALL(self)
		macro_defs.SELECT_ABOVE_WITH_ACE(self, 11)
		macro_defs.INVERT_SELECTION(self)
	else
		macro_defs.KEEP_ALL(self)
		macro_defs.SELECT_ABOVE_WITH_ACE(self, 9)
		macro_defs.SELECT_PAIRS_ABOVE(self, 4)
		macro_defs.INVERT_SELECTION(self)
	end
end
macro_defs.WOODIE = function(self)
	if self.round == 1 then
		macro_defs.KEEP_ALL(self)
		macro_defs.SELECT_PAIRS_ABOVE(self, 4)
		macro_defs.INVERT_SELECTION(self)
	else
		macro_defs.WES(self)
	end
end
macro_defs.WOLFGANG = macro_defs.WES
macro_defs.WILLOW = macro_defs.KEEP_PAIRS
macro_defs.WX78 = function(self)
	if self.round == 1 then
		macro_defs.KEEP_HEARTS(self)
	else
		macro_defs.KEEP_HIGH(self)
		-- Hearts kept in the first deal give +2 mult when discarded now.
		for card_index = 1, 5 do
			if self.notdiscarded and self.notdiscarded[card_index] and self:Suit(card_index) == SUITS.HEARTS then
				self:MarkForDiscard(card_index)
			end
		end
	end
end
macro_defs.WICKERBOTTOM = macro_defs.WES
macro_defs.WAXWELL = function(self)
	if self.round == 1 then
		macro_defs.KEEP_ALL(self)
		macro_defs.SELECT_ABOVE_WITH_ACE(self, 9)
		macro_defs.INVERT_SELECTION(self)
	elseif CountSuit(self, SUITS.HEARTS) + self.mult < 1 then
		macro_defs.WES(self)
	else
		macro_defs.KEEP_ALL(self)
		macro_defs.SELECT_ABOVE_WITH_ACE(self, 9)
		macro_defs.INVERT_SELECTION(self)
		macro_defs.SELECT_SUIT(self, SUITS.HEARTS)
	end
end
macro_defs.WALTER = function(self)
	if self.round == 1 then
		macro_defs.KEEP_ALL(self)
		macro_defs.SELECT_ABOVE_WITH_ACE(self, 9)
		macro_defs.SELECT_PAIRS_ABOVE(self, 4)
		macro_defs.INVERT_SELECTION(self)
	else
		macro_defs.WES(self)
	end
end
macro_defs.WORMWOOD = function(self)
	macro_defs.KEEP_ALL(self)
	macro_defs.SELECT_SUIT(self, SUITS.CLUBS)
	macro_defs.SELECT_PAIRS_ABOVE(self, 4)
	if self.round ~= 1 then
		macro_defs.SELECT_ABOVE_WITH_ACE(self, 10)
	end
	macro_defs.INVERT_SELECTION(self)
end
macro_defs.WANDA = function(self)
	for _, cards in pairs(GroupByNumber(self)) do
		if #cards > 1 then
			macro_defs.KEEP_ALL(self)
			return
		end
	end
	macro_defs.KEEP_HIGH(self)
end
macro_defs.WATHGRITHR = function(self)
	macro_defs.KEEP_ALL(self)
	macro_defs.SELECT_SUIT(self, SUITS.SPADES)
	macro_defs.SELECT_PAIRS_ABOVE(self, 4)
	macro_defs.INVERT_SELECTION(self)
end
macro_defs.WILSON = function(self)
	macro_defs.KEEP_ALL(self)
	if self.round == 1 then
		macro_defs.SELECT_ABOVE_WITH_ACE(self, 10)
		macro_defs.SELECT_PAIRS_ABOVE(self, 4)
		macro_defs.INVERT_SELECTION(self)
		return
	end
	for _, cards in pairs(GroupByNumber(self)) do
		if #cards > 1 then
			macro_defs.SELECT_ABOVE_WITH_ACE(self, 10)
			for _, card_index in ipairs(cards) do self:MarkForDiscard(card_index) end
			macro_defs.INVERT_SELECTION(self)
			return
		end
	end
	macro_defs.SELECT_ABOVE_WITH_ACE(self, 11)
	macro_defs.INVERT_SELECTION(self)
end

--------------------------------------------------------------------------------
-- Text helpers for the AI hints
--------------------------------------------------------------------------------

local SUIT_GLYPHS = {
	"\243\176\128\170", -- spades
	"\243\176\128\141", -- hearts
	"\243\176\128\139", -- clubs
	"\243\176\128\167", -- diamonds
}
local RANK_NAMES = { "A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K" }

local function CardText(gamecard)
	local suit = math.floor(gamecard / 100)
	return RANK_NAMES[gamecard % 100] .. (SUIT_GLYPHS[suit] or "")
end

local function JokerDisplayName(name)
	local display = STRINGS.NAMES[string.upper(name)]
	return string.upper(display or name)
end

local function Pct(p)
	if p == nil then return "..." end
	if p <= 0.0005 then return "-" end
	if p < 0.01 then return "<1%" end
	return string.format("%d%%", math.floor(p * 100 + 0.5))
end

local function ShortName(name)
	local n = JokerDisplayName(name)
	if #n > 7 then n = string.sub(n, 1, 6) .. "." end
	return n
end

local function RerollActive()
	local cb = configs.checkboxes
	return cb.smart and cb.autoplay and cb.replay and cb.auto_reroll
end

local function Loot(dist)
	return dist ~= nil and Brain.ExpectedValue(dist, Brain.PROFILES.balanced) or nil
end

local function DistLine(dist)
	return string.format(STRINGS.BALATRO.TJ.ODDS, Pct(dist[1]), Pct(dist[6] + dist[7] + dist[8]), Pct(dist[8]), Loot(dist))
end

--------------------------------------------------------------------------------
-- The game widget
--------------------------------------------------------------------------------

AddClassPostConstruct("widgets/redux/balatrowidget", function(self)
	local checkboxes = configs.checkboxes

	-- Turbo: process a queue item on every single frame instead of waiting for the delay.
	local _OnUpdate = self.OnUpdate
	self.OnUpdate = function(...)
		self:TJ_RunJob()
		if #self.queue > 0 then
			if checkboxes.turbo and self.queue[1].time ~= nil and self.queue[1].time >= 0 then
				self.queue[1].time = 0
			end
		end
		_OnUpdate(...)
	end

	local _TryToCloseWithAnimations = self.parentscreen.TryToCloseWithAnimations
	self.parentscreen.TryToCloseWithAnimations = function(...)
		if self.root.machine:GetAnimState():IsCurrentAnimation("confetti") and checkboxes.turbo and not checkboxes.skip_ending then
			-- Delay the closing by a second so the player can admire their score!
			-- Players in a rush can still instantly close the screen if they
			-- Click the Back button before the confetti animation
			-- Enabling Skip ending bypasses this
			self.inst:DoTaskInTime(1, function(...)
				_TryToCloseWithAnimations(...)
			end)
		else
			_TryToCloseWithAnimations(...)
		end
	end

	-- Make marking idempotent (the original moves the card every call).
	local _MarkForDiscard = self.MarkForDiscard
	self.MarkForDiscard = function(self, card_index)
		if not self.discard[card_index] then
			if self.halt_card_update then
				self.discard[card_index] = true
			else
				_MarkForDiscard(self, card_index)
				self:TJ_RefreshOdds()
			end
		end
	end

	local _UnmarkForDiscard = self.UnmarkForDiscard
	self.UnmarkForDiscard = function(self, card_index)
		if self.discard[card_index] then
			if self.halt_card_update then
				self.discard[card_index] = false
			else
				_UnmarkForDiscard(self, card_index)
				self:TJ_RefreshOdds()
			end
		end
	end

	function self:Suit(card_index)
		return math.floor(self.slots[card_index] / 100)
	end
	function self:Num(card_index)
		return self.slots[card_index] % 100
	end

	----------------------------------------------------------------------------
	-- Game tracking for the AI (mirrors the server's scoring state)
	----------------------------------------------------------------------------

	self.tj = { hand0 = {} }
	for i = 1, 5 do
		self.tj.hand0[i] = self.slots[i]
	end

	local _choose = self.choose
	self.choose = function(self, ...)
		self:TJ_CancelJob()
		reroll_streak = 0
		local ret = _choose(self, ...)
		local ok, tracker = GLOBAL.pcall(Brain.NewTracker, self.joker, self.tj.hand0)
		self.tj.tracker = ok and tracker or nil
		if not ok then
			print("[Turbo JIMBO] Could not start tracking: " .. tostring(tracker))
		end
		return ret
	end

	local _Deal = self.Deal
	self.Deal = function(self, ...)
		self:TJ_CancelJob()
		self.tj.sent_mask = Brain.MaskFromBools(self.discard)
		return _Deal(self, ...)
	end

	local _ReceiveDeal = self.ReceiveDeal
	self.ReceiveDeal = function(self, ...)
		self:TJ_CancelJob()
		local mask = self.tj.sent_mask or Brain.MaskFromBools(self.discard)
		self.tj.sent_mask = nil
		local ret = _ReceiveDeal(self, ...)
		local tracker = self.tj.tracker
		if tracker ~= nil then
			local ok, err = GLOBAL.pcall(tracker.Record, tracker, mask, self.slots)
			if not ok then
				print("[Turbo JIMBO] Tracking error: " .. tostring(err))
				self.tj.tracker = nil
			elseif tracker.deal >= 3 and not tracker.counted then
				-- Game over: remember the reward rank for the "Played" column.
				tracker.counted = true
				local rank = Brain.RankOf(tracker:FinalScore())
				configs.stats.ranks[rank] = configs.stats.ranks[rank] + 1
				SaveConfigs()
			end
		end
		self:TJ_SetText("")
		self:TJ_RefreshOdds()
		return ret
	end

	-- Returns the tracker if it agrees with what is on screen.
	function self:TJ_GetTracker()
		local tracker = self.tj.tracker
		if tracker == nil or tracker.deal ~= self.round or tracker.deal > 2 then
			return nil
		end
		for i = 1, 5 do
			if Brain.ToGame(tracker.hand[i]) ~= self.slots[i] then
				return nil
			end
		end
		return tracker
	end

	----------------------------------------------------------------------------
	-- Background jobs (the solver runs a little bit every frame)
	----------------------------------------------------------------------------

	function self:TJ_CancelJob()
		self.tj.job = nil
		self.tj.pending_apply = nil
	end

	function self:TJ_StartJob(fn, on_done)
		self:TJ_CancelJob()
		local job = Brain.NewJob(fn, QUOTA)
		job.mode = self.mode
		job.round = self.round
		job.on_done = on_done
		self.tj.job = job
	end

	function self:TJ_RunJob()
		local job = self.tj.job
		if job == nil then
			return
		end
		local t0 = Now()
		local steps = 0
		while true do
			local done = job:Step()
			steps = steps + 1
			if done then
				if self.tj.job == job then
					self.tj.job = nil
				end
				if job.error ~= nil then
					print("[Turbo JIMBO] AI error: " .. tostring(job.error))
				end
				if job.mode == self.mode and job.round == self.round then
					job.on_done(job.error == nil and job.result or nil)
				end
				return
			end
			if steps >= MAX_STEPS_PER_FRAME or (t0 ~= nil and Now() - t0 >= FRAME_BUDGET) or (t0 == nil and steps >= 4) then
				return
			end
		end
	end

	----------------------------------------------------------------------------
	-- Hint text
	----------------------------------------------------------------------------

	self.root.tj_text = self.root:AddChild(Text(GLOBAL.CHATFONT_OUTLINE, 20, "", GLOBAL.UICOLOURS.GOLD))
	self.root.tj_text:SetPosition(105, -315, 0)
	self.root.tj_text:SetRegionSize(400, 46)
	self.root.tj_text:EnableWordWrap(true)

	function self:TJ_SetText(str)
		if self.root.tj_text ~= nil then
			self.root.tj_text:SetString(str or "")
		end
	end

	----------------------------------------------------------------------------
	-- ODDS panel: the chance of every reward tier
	----------------------------------------------------------------------------

	local ODDS_ROW_Y0, ODDS_ROW_DY = 122, 22
	local ODDS_MAX_COLS = 5
	local ODDS_X0, ODDS_X1 = -45, 200

	function self:TJ_ShowOdds(show)
		local panel = self.root.game_odds
		if panel == nil then
			return
		end
		if show then
			panel:MoveToFront()
			panel:Show()
			panel.showing = true
			self:TJ_RefreshOdds()
		else
			panel:Hide()
			panel.showing = false
		end
	end

	-- Columns for the current state: { header=, dist=, highlight=, empty= }
	function self:TJ_OddsColumns()
		local cols = {}
		if checkboxes.smart then
			if self.mode == "joker" then
				local names = self:TJ_JokerNames()
				local advice = self.tj.joker_advice
				for i = 1, 3 do
					if names[i] ~= nil then
						local best = advice ~= nil and advice.best == i
						table.insert(cols, {
							header = (best and "*" or "") .. ShortName(names[i]),
							dist = advice ~= nil and advice.dists[i] or nil,
							highlight = best,
						})
					end
				end
			elseif self.mode == "deal" and self.round < 3 then
				local advice = self.tj.deal_advice
				if advice ~= nil and advice.round ~= self.round then
					advice = nil
				end
				local info = advice ~= nil and advice.info or nil
				table.insert(cols, { header = STRINGS.BALATRO.TJ.COL_AI, dist = info ~= nil and info.dist or nil, highlight = true })
				if info ~= nil and info.dists ~= nil then
					-- Final deal: exact odds for the cards currently marked.
					table.insert(cols, { header = STRINGS.BALATRO.TJ.COL_MARKED, dist = info.dists[Brain.MaskFromBools(self.discard)] })
				end
			end
		end
		local reroll = RerollActive() and configs.ai.reroll or nil
		table.insert(cols, { header = STRINGS.BALATRO.TJ.COL_AVG, dist = AvgStats.Get(configs.ai.goal, reroll), empty = true })
		local played = 0
		for r = 1, 8 do
			played = played + configs.stats.ranks[r]
		end
		local pdist
		if played > 0 then
			pdist = {}
			for r = 1, 8 do
				pdist[r] = configs.stats.ranks[r] / played
			end
		end
		table.insert(cols, { header = STRINGS.BALATRO.TJ.COL_PLAYED, dist = pdist, empty = true })
		return cols, played
	end

	function self:TJ_RefreshOdds()
		local panel = self.root.game_odds
		if panel == nil or not panel.showing then
			return
		end
		local cols, played = self:TJ_OddsColumns()
		local n = math.min(#cols, ODDS_MAX_COLS)
		for c = 1, ODDS_MAX_COLS do
			local col = c <= n and cols[c] or nil
			local x = n > 1 and (ODDS_X0 + (c - 1) * (ODDS_X1 - ODDS_X0) / (n - 1)) or ODDS_X1
			for row = 0, 9 do
				local cell = panel.cells[row][c]
				if col == nil then
					cell:SetString("")
				else
					cell:SetPosition(x, panel.rowy[row], 0)
					local missing = col.empty and "-" or "..."
					if row == 0 then
						cell:SetString(col.header)
						cell:SetColour(col.highlight and GLOBAL.UICOLOURS.GOLD or GLOBAL.UICOLOURS.WHITE)
					elseif row <= 8 then
						cell:SetString(col.dist ~= nil and Pct(col.dist[row]) or missing)
					else
						cell:SetString(col.dist ~= nil and string.format("%.1f", Loot(col.dist)) or missing)
					end
				end
			end
		end
		local reroll = RerollActive() and configs.ai.reroll or nil
		panel.subtitle:SetString(string.format(STRINGS.BALATRO.TJ.ODDS_SUBTITLE,
			OptionText(GOAL_OPTIONS, configs.ai.goal),
			OptionText(BUDGET_OPTIONS, configs.ai.budget),
			reroll ~= nil and OptionText(REROLL_OPTIONS, reroll) or STRINGS.BALATRO.TJ.OFF))
		panel.footer:SetString(string.format(STRINGS.BALATRO.TJ.ODDS_FOOTER,
			AvgStats.Rerolls(configs.ai.goal, reroll), played, configs.stats.rerolls))
	end

	----------------------------------------------------------------------------
	-- Smart AI: joker choice (+ optional reroll)
	----------------------------------------------------------------------------

	function self:TJ_JokerNames()
		local names = {}
		for i = 1, 3 do
			local card = self.root["joker_card" .. i]
			names[i] = card ~= nil and card.joker_selected ~= nil and card.joker_selected.name or nil
		end
		return names
	end

	function self:TJ_ApplyJokerAdvice(also_choose)
		local advice = self.tj.joker_advice
		if advice == nil or self.mode ~= "joker" then
			return
		end
		self:SelectJoker(advice.best)
		if also_choose then
			self:choose()
		end
	end

	function self:TJ_Reroll()
		if self.mode ~= "joker" then
			return -- Never close once a joker is chosen, that spawns monsters!
		end
		self:TJ_CancelJob()
		self:TJ_SetText(STRINGS.BALATRO.TJ.REROLLING)
		configs.stats.rerolls = configs.stats.rerolls + 1
		SaveConfigs()
		self.root.close.onclick()
	end

	function self:TJ_OnJokerAdvice(result)
		if result == nil then
			-- Solver failed, fall back to the classic ranking.
			if checkboxes.autoplay then
				macro_defs.CHOOSE_JOKER(self)
				self:choose()
			end
			return
		end
		local best, values, dists, names = result[1], result[2], result[3] or {}, self:TJ_JokerNames()
		if best == nil or values == nil or values[best] == nil or values[best] < -1e8 then
			if checkboxes.autoplay then
				macro_defs.CHOOSE_JOKER(self)
				self:choose()
			end
			return
		end
		self.tj.joker_advice = { best = best, values = values, dists = dists }

		local others = {}
		for i = 1, 3 do
			if i ~= best and names[i] ~= nil then
				local v = Loot(dists[i])
				table.insert(others, JokerDisplayName(names[i]) .. " " .. (v ~= nil and string.format("%.1f", v) or "?"))
			end
		end
		local best_loot = Loot(dists[best]) or 0
		local weak = best_loot < configs.ai.reroll
		self:TJ_SetText(string.format(STRINGS.BALATRO.TJ.JOKER_HINT, JokerDisplayName(names[best]), best_loot, table.concat(others, ", "))
			.. (weak and ("\n" .. STRINGS.BALATRO.TJ.WEAK_START) or ""))
		self:TJ_RefreshOdds()

		if checkboxes.autoplay then
			if weak and checkboxes.auto_reroll and checkboxes.replay and reroll_streak < MAX_REROLLS_IN_A_ROW then
				reroll_streak = reroll_streak + 1
				self:TJ_Reroll()
			else
				self:TJ_ApplyJokerAdvice(true)
			end
		elseif self.tj.pending_apply then
			self.tj.pending_apply = nil
			self:TJ_ApplyJokerAdvice(checkboxes.macros_end_round)
		end
	end

	function self:TJ_AnalyzeJokers()
		local names = self:TJ_JokerNames()
		local hand = {}
		for i = 1, 5 do hand[i] = self.tj.hand0[i] end
		self:TJ_SetText(STRINGS.BALATRO.TJ.THINKING)
		self:TJ_StartJob(function()
			return Brain.ChooseJoker(names, hand, Utility(), BrainOpts())
		end, function(result)
			self:TJ_OnJokerAdvice(result)
		end)
	end

	----------------------------------------------------------------------------
	-- Smart AI: discards
	----------------------------------------------------------------------------

	function self:TJ_ApplyMask(mask)
		local bits = Brain.MASK_BITS[mask]
		for i = 1, 5 do
			if bits[i] then
				self:MarkForDiscard(i)
			else
				self:UnmarkForDiscard(i)
			end
		end
	end

	function self:TJ_ApplyDealAdvice(also_deal)
		local advice = self.tj.deal_advice
		if advice == nil or advice.round ~= self.round or self.mode ~= "deal" or self.waitingtime ~= nil then
			return
		end
		self:TJ_ApplyMask(advice.mask)
		if also_deal then
			self:Deal()
		end
	end

	function self:TJ_OnDealAdvice(result)
		if result == nil or result[1] == nil then
			if checkboxes.autoplay then
				self:AutoPlayClassic()
			end
			return
		end
		local mask, info = result[1], result[2]
		self.tj.deal_advice = { mask = mask, info = info, round = self.round }

		local bits = Brain.MASK_BITS[mask]
		local cards = {}
		for i = 1, 5 do
			if bits[i] then
				table.insert(cards, CardText(self.slots[i]))
			end
		end
		local action = #cards == 0 and STRINGS.BALATRO.TJ.KEEP_ALL
			or (#cards == 5 and STRINGS.BALATRO.TJ.DISCARD_ALL)
			or string.format(STRINGS.BALATRO.TJ.DISCARD, table.concat(cards, " "))
		local str = action
		if info ~= nil and info.dist ~= nil then
			str = str .. "\n" .. DistLine(info.dist)
		end
		self:TJ_SetText(str)
		self:TJ_RefreshOdds()

		if checkboxes.autoplay then
			self:TJ_ApplyDealAdvice(true)
		elseif self.tj.pending_apply then
			self.tj.pending_apply = nil
			self:TJ_ApplyDealAdvice(checkboxes.macros_end_round)
		end
	end

	function self:TJ_AnalyzeDeal()
		local tracker = self:TJ_GetTracker()
		if tracker == nil then
			self:TJ_SetText("")
			return false
		end
		self.tj.deal_advice = nil
		self:TJ_SetText(STRINGS.BALATRO.TJ.THINKING)
		self:TJ_RefreshOdds()
		self:TJ_StartJob(function()
			return Brain.DecideDiscard(tracker, Utility(), BrainOpts())
		end, function(result)
			self:TJ_OnDealAdvice(result)
		end)
		return true
	end

	----------------------------------------------------------------------------
	-- Rearrange existing buttons to fit configs button
	----------------------------------------------------------------------------

	self.root.notes:SetScale(0.66)
	self.root.notes:SetPosition(14, -220, 0)

	self.root.deal:SetScale(0.66)
	self.root.deal:SetPosition(195, -220, 0)

	self.root.close:SetScale(0.66)
	self.root.close:SetPosition(286, -220, 0)

	-- Hide configs when notes are shown
	self.root.notes:SetOnClick(function()
		if not self.root.game_notes.showing then
			self.root.game_notes:MoveToFront()
			self.root.game_notes:Show()
			self.root.game_notes.showing = true
		else
			self.root.game_notes:Hide()
			self.root.game_notes.showing = false
		end
		if self.root.game_configs.showing then
			self.root.game_configs:Hide()
			self.root.game_configs.showing = false
		end
		self:TJ_ShowOdds(false)
	end)

	-- Create the configs button
	self.root.configs = self.root:AddChild(ImageButton("images/balatro.xml", "button_normal.tex", "button_focus.tex", "button_disabled.tex", "button_normal.tex", "button_focus.tex", { 0.7, 0.7, 0.7 }))
	self.root.configs:SetPosition(105, -220, 0)
	self.root.configs:SetScale(0.66)
	self.root.configs:SetTextSize(25)
	self.root.configs:SetNormalScale(0.7, 0.7, 0.7)
	self.root.configs:SetFocusScale(0.75, 0.75, 0.75)
	self.root.configs:SetText(STRINGS.BALATRO.BUTTON_CONFIGS)
	self.root.configs:SetOnClick(function()
		if not self.root.game_configs.showing then
			self.root.game_configs:MoveToFront()
			self.root.game_configs:Show()
			self.root.game_configs.showing = true
		else
			self.root.game_configs:Hide()
			self.root.game_configs.showing = false
		end
		if self.root.game_notes.showing then
			self.root.game_notes:Hide()
			self.root.game_notes.showing = false
		end
		self:TJ_ShowOdds(false)
	end)

	-- Create the configs screen
	self.root.game_configs = self.root:AddChild(UIAnim())
	local game_configs_anim_state = self.root.game_configs:GetAnimState()
	game_configs_anim_state:SetBuild("ui_balatro")
	game_configs_anim_state:SetBank("ui_balatro")
	game_configs_anim_state:PlayAnimation("green_idle", true)
	self.root.game_configs:SetPosition(150, -40, 0)
	self.root.game_configs:Hide()

	local function AddCheckbox(key, label, x, y, on_change)
		local checkbox = self.root.game_configs:AddChild(Templates.LabelCheckbox(function(checkbox)
			checkboxes[key] = not checkboxes[key]
			checkbox.checked = checkboxes[key]
			SaveConfigs()
			checkbox:Refresh()
			if on_change ~= nil then
				on_change(checkboxes[key])
			end
		end, checkboxes[key], label))
		checkbox:SetPosition(x, y, 0)
		return checkbox
	end

	local COL1, COL2 = -180, 0
	local ROW1, ROW2, ROW3, ROW4 = 160, 128, 96, 64
	self.root.game_configs.turbo_checkbox = AddCheckbox("turbo", STRINGS.BALATRO.CONFIGS_TURBO, COL1, ROW1)
	self.root.game_configs.replay_checkbox = AddCheckbox("replay", STRINGS.BALATRO.CONFIGS_REPLAY, COL1, ROW2, function()
		self:TJ_RefreshOdds()
	end)
	self.root.game_configs.autoplay_checkbox = AddCheckbox("autoplay", STRINGS.BALATRO.CONFIGS_AUTOPLAY, COL1, ROW3, function(enabled)
		if enabled then
			-- Disable macros if autoplay is enabled during round, but do not enable if autoplay is turned off
			self:EnableMacros(false)
		end
		self:TJ_RefreshOdds()
	end)
	self.root.game_configs.skip_ending_checkbox = AddCheckbox("skip_ending", STRINGS.BALATRO.CONFIGS_SKIP_ENDING, COL1, ROW4)
	self.root.game_configs.reveal_cards_checkbox = AddCheckbox("reveal_cards", STRINGS.BALATRO.CONFIGS_REVEAL_CARDS, COL2, ROW1)
	self.root.game_configs.macros_end_round_checkbox = AddCheckbox("macros_end_round", STRINGS.BALATRO.CONFIGS_MACROS_END_ROUND, COL2, ROW2)
	self.root.game_configs.smart_checkbox = AddCheckbox("smart", STRINGS.BALATRO.CONFIGS_SMART, COL2, ROW3, function(enabled)
		self:TJ_UpdateConfigSections()
		self:TJ_OnSettingsChanged()
	end)
	self.root.game_configs.auto_reroll_checkbox = AddCheckbox("auto_reroll", STRINGS.BALATRO.CONFIGS_AUTO_REROLL, COL2, ROW4, function()
		self:TJ_RefreshOdds()
	end)

	-- Called when an AI setting changes: drop the running analysis and redo it.
	function self:TJ_OnSettingsChanged()
		self:TJ_CancelJob()
		self:TJ_SetText("")
		self.tj.joker_advice = nil
		self.tj.deal_advice = nil
		self:TJ_RefreshOdds()
		if checkboxes.autoplay then
			return
		end
		local can_act = self.mode == "joker" or (self.mode == "deal" and self.root.deal.enabled ~= false and self.waitingtime == nil and self.round < 3)
		self:EnableMacros(can_act)
		if checkboxes.smart and can_act then
			if self.mode == "joker" then
				self:TJ_AnalyzeJokers()
			else
				self:TJ_AnalyzeDeal()
			end
		end
	end

	-- Smart AI settings (shown instead of the joker ranking while Smart AI is on)
	local ai_section = self.root.game_configs:AddChild(Widget("tj_ai_section"))
	self.root.game_configs.ai_section = ai_section
	ai_section.title = ai_section:AddChild(Text(GLOBAL.CHATFONT_OUTLINE, 24, STRINGS.BALATRO.TJ.SETTINGS_TITLE, GLOBAL.UICOLOURS.GOLD))
	ai_section.title:SetPosition(0, 28, 0)
	local function AddSpinner(label, options, key, y)
		local w = ai_section:AddChild(Templates.LabelSpinner(label, options, 180, 220, 34, 8, GLOBAL.CHATFONT_OUTLINE, 22))
		w:SetPosition(0, y, 0)
		w.spinner:SetSelected(configs.ai[key])
		w.spinner:SetOnChangedFn(function(data)
			configs.ai[key] = data
			SaveConfigs()
			self:TJ_OnSettingsChanged()
		end)
		return w
	end
	ai_section.goal = AddSpinner(STRINGS.BALATRO.TJ.SETTING_GOAL, GOAL_OPTIONS, "goal", -6)
	ai_section.budget = AddSpinner(STRINGS.BALATRO.TJ.SETTING_BUDGET, BUDGET_OPTIONS, "budget", -42)
	ai_section.reroll = AddSpinner(STRINGS.BALATRO.TJ.SETTING_REROLL, REROLL_OPTIONS, "reroll", -78)
	ai_section.note = ai_section:AddChild(Text(GLOBAL.CHATFONT_OUTLINE, 17, STRINGS.BALATRO.TJ.SETTINGS_NOTE, GLOBAL.UICOLOURS.GOLD))
	ai_section.note:SetPosition(0, -112, 0)
	ai_section.note:SetRegionSize(420, 40)
	ai_section.note:EnableWordWrap(true)

	-- Create the jokers ranking (used when Smart AI is off)
	-- Lower rank number: more preferable
	local rank_section = self.root.game_configs:AddChild(Widget("tj_rank_section"))
	self.root.game_configs.rank_section = rank_section
	self.root.game_configs.joker_rank_cards = {}
	for rank, name in ipairs(configs.jokers_rank) do
		self.root.game_configs.joker_rank_cards[rank] = rank_section:AddChild(UIAnimButton("balatro_machine", "balatro_machine", "card_idle", "card_idle", "card_idle", "card_idle", "card_idle"))
		local card = self.root.game_configs.joker_rank_cards[rank]
		card.rank = rank

		function card.UpdateCardArt(this_card)
			this_card.uianim:GetAnimState():OverrideSymbol("swap_card1", "balatro_jokers", "joker_" .. configs.jokers_rank[this_card.rank])
		end
		card:UpdateCardArt()
		card.uianim:GetAnimState():OverrideSymbol("swap_suit1", "balatro_machine", "null")
		card.uianim:GetAnimState():OverrideSymbol("swap_number1", "balatro_machine", "null")
		card.uianim:GetAnimState():SetBuild("balatro_machine")
		card.uianim:GetAnimState():SetBank("balatro_machine")
		card.uianim:GetAnimState():PlayAnimation("card_idle", true)
		card:SetScale(0.30)
		-- Create 2 rows of 9 cards
		if rank < 10 then
			card:SetPosition(-225 + 45 * rank, -11, 0)
		else
			card:SetPosition(-630 + 45 * rank, -72, 0)
		end

		card:SetOnClick(function()
			if self.root.game_configs.selected_joker then
				if self.root.game_configs.selected_joker ~= card then
					-- Swap selected cards and save preference
					local selected = self.root.game_configs.selected_joker
					local card_name = configs.jokers_rank[card.rank]
					configs.jokers_rank[card.rank] = configs.jokers_rank[selected.rank]
					configs.jokers_rank[selected.rank] = card_name
					SaveConfigs()
					selected:UpdateCardArt()
					card:UpdateCardArt()
					selected.uianim:GetAnimState():SetSymbolMultColour("swap_card1", 1, 1, 1, 1)
				else
					card.uianim:GetAnimState():SetSymbolMultColour("swap_card1", 1, 1, 1, 1)
				end
				self.root.game_configs.selected_joker = nil
			else
				card.uianim:GetAnimState():SetSymbolMultColour("swap_card1", 0.7, 0.7, 0.7, 1)
				self.root.game_configs.selected_joker = card
			end
		end)
	end

	-- Descriptions for the jokers ranking
	self.root.game_configs.most_preferred_text = rank_section:AddChild(Text(GLOBAL.CHATFONT_OUTLINE, 25, "", GLOBAL.UICOLOURS.GOLD))
	self.root.game_configs.most_preferred_text:SetString(STRINGS.BALATRO.CONFIGS_MOST_PREFERRED_TEXT)
	self.root.game_configs.most_preferred_text:SetPosition(-90, 30, 0)
	self.root.game_configs.most_preferred_text:SetHAlign(GLOBAL.ANCHOR_LEFT)

	self.root.game_configs.least_preferred_text = rank_section:AddChild(Text(GLOBAL.CHATFONT_OUTLINE, 25, "", GLOBAL.UICOLOURS.GOLD))
	self.root.game_configs.least_preferred_text:SetString(STRINGS.BALATRO.CONFIGS_LEAST_PREFERRED_TEXT)
	self.root.game_configs.least_preferred_text:SetPosition(90, -116, 0)
	self.root.game_configs.least_preferred_text:SetHAlign(GLOBAL.ANCHOR_RIGHT)

	-- The joker ranking is only used when Smart AI is off; otherwise show the AI settings there.
	function self:TJ_UpdateConfigSections()
		local gc = self.root.game_configs
		if checkboxes.smart then
			gc.ai_section:Show()
			gc.rank_section:Hide()
		else
			gc.ai_section:Hide()
			gc.rank_section:Show()
		end
	end
	self:TJ_UpdateConfigSections()

	-- Keep references for other mods
	self.SUITS = SUITS
	self.root.macro_tree = macro_tree
	self.root.macro_defs = macro_defs

	----------------------------------------------------------------------------
	-- Macro buttons
	----------------------------------------------------------------------------

	-- Returns label, onclick for macro button 1 or 2 in the current state.
	local function GetMacro(macro_index)
		if checkboxes.smart then
			if self.mode == "joker" then
				if macro_index == 1 then
					return STRINGS.BALATRO.MACROS.BEST_JOKER, function()
						if self.tj.joker_advice ~= nil then
							self:TJ_ApplyJokerAdvice(checkboxes.macros_end_round)
						else
							if self.tj.job == nil then
								self:TJ_AnalyzeJokers()
							end
							self.tj.pending_apply = true
						end
					end
				else
					return STRINGS.BALATRO.MACROS.REROLL, function()
						self:TJ_Reroll()
					end
				end
			elseif self.mode == "deal" and macro_index == 1 then
				return STRINGS.BALATRO.MACROS.BEST_MOVE, function()
					local advice = self.tj.deal_advice
					if advice ~= nil and advice.round == self.round then
						self:TJ_ApplyDealAdvice(checkboxes.macros_end_round)
					else
						if self.tj.job == nil then
							self:TJ_AnalyzeDeal()
						end
						self.tj.pending_apply = true
					end
				end
			end
			return nil
		end

		local macro_name = macro_tree[self.mode] and macro_tree[self.mode][macro_index]
		if self.mode == "deal" then
			macro_name = macro_tree.deal[self.joker] and macro_tree.deal[self.joker][macro_index]
		end
		if macro_name ~= nil then
			return STRINGS.BALATRO.MACROS[macro_name] or "", function()
				macro_defs[macro_name](self)
				if checkboxes.macros_end_round then
					self.root.deal.onclick()
				end
			end
		end
		return nil
	end

	for macro_index = 1, 2 do
		self.root["macro" .. macro_index] = self.root:AddChild(ImageButton("images/balatro.xml", "button_normal.tex", "button_focus.tex", "button_disabled.tex", "button_normal.tex", "button_focus.tex", { 0.7, 0.7, 0.7 }))
		local macro = self.root["macro" .. macro_index]
		macro:SetScale(0.66)
		macro:SetTextSize(25)
		macro:SetNormalScale(0.7, 0.7, 0.7)
		macro:SetFocusScale(0.75, 0.75, 0.75)
		function macro.Update(this_macro, set)
			local label, onclick = GetMacro(macro_index)
			if label ~= nil then
				this_macro:SetOnClick(onclick)
				this_macro:SetText(label)
				if set then
					this_macro:Enable()
				else
					this_macro:Disable()
				end
			else
				this_macro:SetText("")
				this_macro:Disable()
			end
		end
	end
	self.root.macro1:SetPosition(195, -270, 0)
	self.root.macro2:SetPosition(286, -270, 0)

	-- ODDS button (under CONFIGS) and panel
	self.root.odds = self.root:AddChild(ImageButton("images/balatro.xml", "button_normal.tex", "button_focus.tex", "button_disabled.tex", "button_normal.tex", "button_focus.tex", { 0.7, 0.7, 0.7 }))
	self.root.odds:SetPosition(105, -270, 0)
	self.root.odds:SetScale(0.66)
	self.root.odds:SetTextSize(25)
	self.root.odds:SetNormalScale(0.7, 0.7, 0.7)
	self.root.odds:SetFocusScale(0.75, 0.75, 0.75)
	self.root.odds:SetText(STRINGS.BALATRO.MACROS.ODDS)
	self.root.odds:SetOnClick(function()
		local show = not self.root.game_odds.showing
		if show then
			if self.root.game_notes.showing then
				self.root.game_notes:Hide()
				self.root.game_notes.showing = false
			end
			if self.root.game_configs.showing then
				self.root.game_configs:Hide()
				self.root.game_configs.showing = false
			end
		end
		self:TJ_ShowOdds(show)
	end)

	local panel = self.root:AddChild(UIAnim())
	self.root.game_odds = panel
	panel:GetAnimState():SetBuild("ui_balatro")
	panel:GetAnimState():SetBank("ui_balatro")
	panel:GetAnimState():PlayAnimation("green_idle", true)
	panel:SetPosition(150, -40, 0)
	panel:Hide()
	panel.showing = false
	panel.title = panel:AddChild(Text(GLOBAL.CHATFONT_OUTLINE, 26, STRINGS.BALATRO.TJ.ODDS_TITLE, GLOBAL.UICOLOURS.GOLD))
	panel.title:SetPosition(0, 168, 0)
	panel.subtitle = panel:AddChild(Text(GLOBAL.CHATFONT_OUTLINE, 17, "", GLOBAL.UICOLOURS.GOLD))
	panel.subtitle:SetPosition(0, 146, 0)
	panel.subtitle:SetRegionSize(460, 22)
	panel.rowy = {}
	panel.cells = {}
	for row = 0, 9 do
		local y = ODDS_ROW_Y0 - ODDS_ROW_DY * row - (row == 9 and 4 or 0)
		panel.rowy[row] = y
		local label_text = row == 0 and STRINGS.BALATRO.TJ.COL_REWARD
			or (row == 9 and STRINGS.BALATRO.TJ.ROW_LOOT or STRINGS.BALATRO.TJ.TIERS[row])
		local label = panel:AddChild(Text(GLOBAL.CHATFONT_OUTLINE, 19, label_text, GLOBAL.UICOLOURS.GOLD))
		label:SetRegionSize(160, 24)
		label:SetHAlign(GLOBAL.ANCHOR_LEFT)
		label:SetPosition(-165, y, 0)
		panel.cells[row] = {}
		for c = 1, ODDS_MAX_COLS do
			local cell = panel:AddChild(Text(GLOBAL.CHATFONT_OUTLINE, 19, "", GLOBAL.UICOLOURS.WHITE))
			cell:SetRegionSize(66, 24)
			cell:SetPosition(0, y, 0)
			panel.cells[row][c] = cell
		end
	end
	panel.footer = panel:AddChild(Text(GLOBAL.CHATFONT_OUTLINE, 16, "", GLOBAL.UICOLOURS.GOLD))
	panel.footer:SetPosition(0, -112, 0)
	panel.footer:SetRegionSize(460, 40)
	panel.footer:EnableWordWrap(true)

	function self:EnableMacros(set)
		self.root.macro1:Update(set)
		self.root.macro2:Update(set)
	end
	self:EnableMacros(not checkboxes.autoplay)

	----------------------------------------------------------------------------
	-- Autoplay
	----------------------------------------------------------------------------

	-- Classic autoplay (Smart AI off, or as a fallback if the AI fails)
	function self:AutoPlayClassic()
		if self.mode == "joker" then
			macro_defs.CHOOSE_JOKER(self)
			self:choose()
		elseif self.mode == "deal" then
			local before, wanted = {}, {}
			for card_index = 1, 5 do
				before[card_index] = self.discard[card_index] == true
			end
			self.halt_card_update = true
			local fn = macro_defs[string.upper(self.joker)]
			if fn ~= nil then
				fn(self)
			end
			self.halt_card_update = false
			for card_index = 1, 5 do
				wanted[card_index] = self.discard[card_index] == true
				self.discard[card_index] = before[card_index] -- restore, then apply with visuals
			end
			self:TJ_ApplyMask(Brain.MaskFromBools(wanted))
			self:Deal()
		end
	end

	function self:AutoPlay()
		if checkboxes.smart then
			if self.mode == "joker" then
				self:TJ_AnalyzeJokers()
				return
			elseif self.mode == "deal" and self:TJ_AnalyzeDeal() then
				return
			end
		end
		self:AutoPlayClassic()
	end

	local _EnableDealButton = self.EnableDealButton
	self.EnableDealButton = function(self, set)
		if checkboxes.skip_ending and self.round >= 3 then
			self.parentscreen:TryToCloseWithAnimations()
		end
		_EnableDealButton(self, set)
		if checkboxes.autoplay then
			if set and self.mode == "deal" then
				self:AutoPlay()
			end
		else
			self:EnableMacros(set)
			if set and self.mode == "deal" and checkboxes.smart then
				self:TJ_AnalyzeDeal() -- show the hint
			end
		end
	end

	-- Reveal cards at the start (simultaneously)
	if checkboxes.reveal_cards then
		table.insert(self.queue, { time = 3 * GLOBAL.FRAMES, fn = function()
			for card_index = 1, 5 do
				self.root.machine["card" .. card_index].uianim:GetAnimState():PlayAnimation("card_flip")
				GLOBAL.TheFrontEnd:GetSound():PlaySound("balatro/balatro_cabinet/cards_flip_HUD")
			end
		end })
		table.insert(self.queue, { time = 6 * GLOBAL.FRAMES, fn = function()
			for card_index = 1, 5 do
				self:UpdateCardArt(card_index)
			end
		end })
	end

	-- Initiate autoplay / the joker hint
	if checkboxes.autoplay then
		self:AutoPlay()
	elseif checkboxes.smart then
		self:TJ_AnalyzeJokers()
	end
end)

-- Do not replay if the player is busy
AddPlayerPostInit(function(inst)
	inst.interrupt_tags = {
		"attack",
		"doing",
		"running",
		"moving",
		"working",
	}
	function inst.CanPlayBalatro(inst)
		for i, tag in pairs(inst.interrupt_tags) do
			if inst:HasTag(tag) then
				return false
			end
		end
		return true
	end
end)

-- Store the machine pointer so we can retarget it
local _POPUPS_BALATRO_fn = GLOBAL.POPUPS.BALATRO.fn
GLOBAL.POPUPS.BALATRO.fn = function(inst, show, target, ...)
	_POPUPS_BALATRO_fn(inst, show, target, ...)
	if show and target then
		inst.balatro_machine = target
	end
end

-- Queue replay after game ends
local _POPUPS_BALATRO_Close = GLOBAL.POPUPS.BALATRO.Close
GLOBAL.POPUPS.BALATRO.Close = function(self, inst, target, ...)
	_POPUPS_BALATRO_Close(self, inst, target, ...)
	-- Check if player exists and whether replay is already queued
	if inst ~= nil and not (inst.balatro_replay_task and inst.balatro_replay_task.fn) and configs.checkboxes.replay then
		inst.balatro_replay_task = inst:DoPeriodicTask(GLOBAL.FRAMES, function(inst)
			-- Check if machine still exists and replay is still on, otherwise cancel queue
			if inst.balatro_machine ~= nil and inst.balatro_machine:IsValid() and configs.checkboxes.replay then
				-- Check if machine is ready to play, otherwise wait
				if inst.balatro_machine.components.activatable and inst.balatro_machine.components.activatable:CanActivate(inst) or inst.balatro_machine:HasTag("inactive") then
					-- Check if player is ready to play. Cancel queue anyway if player is busy
					if inst:CanPlayBalatro() then
						if inst.components.playercontroller and inst.components.playercontroller:CanLocomote() then
							-- Server side control
							local replay_buffaction = GLOBAL.BufferedAction(inst, inst.balatro_machine, GLOBAL.ACTIONS.ACTIVATE)
							replay_buffaction.preview_cb = function()
								-- Preview for lag compensation
								GLOBAL.SendRPCToServer(GLOBAL.RPC.ActionButton, GLOBAL.ACTIONS.ACTIVATE.code, inst.balatro_machine)
							end
							inst.components.playercontroller:DoAction(replay_buffaction)
						else
							-- Client side control
							local x, y, z = inst.Transform:GetWorldPosition()
							GLOBAL.SendRPCToServer(GLOBAL.RPC.LeftClick, GLOBAL.ACTIONS.ACTIVATE.code, x, z, inst.balatro_machine)
						end
					end
					inst.balatro_replay_task:Cancel()
				end
			else
				inst.balatro_replay_task:Cancel()
			end
		end)
	end
end
