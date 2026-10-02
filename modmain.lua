local ImageButton = require("widgets/imagebutton")
local Text = require("widgets/text")
local UIAnim = require("widgets/uianim")
local UIAnimButton = require("widgets/uianimbutton")
local Widget = require("widgets/widget")
local Templates = require("widgets/redux/templates")
local PersistentData = require("persistentdata")
local Brain = require("turbojimbo_brain")
local Profiles = require("turbojimbo_profiles")
modimport("scripts/strings.lua")

local STRINGS = GLOBAL.STRINGS

--------------------------------------------------------------------------------
-- Smart AI settings (edited in the in-game CONFIGS panel, saved with the mod data)
--------------------------------------------------------------------------------

local BUDGET_OPTIONS = {
	{ text = "Fast", data = 0.5 },
	{ text = "Normal", data = 1 },
	{ text = "Deep", data = 2 },
	{ text = "Very deep", data = 4 },
}
local MAX_REROLLS_IN_A_ROW = 40
local MAX_CUSTOM_PROFILES = 12

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

--------------------------------------------------------------------------------
-- Profiles: presets (read-only) + the player's own (saved in configs.profiles)
--------------------------------------------------------------------------------

local function AllProfiles()
	local t = {}
	for _, p in ipairs(Profiles.PRESETS) do t[#t + 1] = p end
	for _, p in ipairs(configs.profiles) do t[#t + 1] = p end
	return t
end

local function FindProfile(id)
	for _, p in ipairs(AllProfiles()) do
		if p.id == id then return p end
	end
	return nil
end

local function ActiveProfile()
	return FindProfile(configs.ai.profile) or Profiles.PRESETS[1]
end

local function ProfileOptions()
	local options = {}
	for _, p in ipairs(AllProfiles()) do
		options[#options + 1] = { text = p.name, data = p.id }
	end
	return options
end

local function Utility()
	return ActiveProfile().util
end

-- "Reroll the worst X% of start configurations" (global setting). "auto" = best EV/min.
local function RerollShare()
	local v = configs.ai.reroll_share
	if v == "auto" then return "auto" end
	return v / 100
end

local function RerollShareOptions()
	local options = {}
	for _, v in ipairs(Profiles.REROLL_SHARES) do
		local text = v == "auto" and STRINGS.BALATRO.TJ.SHARE_AUTO
			or (v == 0 and STRINGS.BALATRO.TJ.SHARE_NEVER or string.format(STRINGS.BALATRO.TJ.SHARE_WORST, v))
		options[#options + 1] = { text = text, data = v }
	end
	return options
end

-- Long-run summary of a profile; rerolls_on = whether starts are actually rerolled.
local function ProfileSummary(profile, rerolls_on)
	return Profiles.Summary(profile, rerolls_on and RerollShare() or 0)
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
-- v0.6 had a fixed "goal" and a global reroll threshold: the goal becomes the profile.
if configs.ai.profile == nil and type(configs.ai.goal) == "string" then
	configs.ai.profile = configs.ai.goal
end
configs.ai.goal = nil
configs.ai.reroll = nil
local share_ok = false
for _, v in ipairs(Profiles.REROLL_SHARES) do
	if v == configs.ai.reroll_share then share_ok = true end
end
if not share_ok then
	configs.ai.reroll_share = "auto"
end
if not IsOption(BUDGET_OPTIONS, configs.ai.budget) then configs.ai.budget = 1 end
local saved_profiles = type(configs.profiles) == "table" and configs.profiles or {}
configs.profiles = {}
for _, saved in ipairs(saved_profiles) do
	local profile = Profiles.Sanitize(saved)
	if profile ~= nil and FindProfile(profile.id) == nil then
		table.insert(configs.profiles, profile)
	end
end
if FindProfile(configs.ai.profile) == nil then
	configs.ai.profile = "balanced"
end
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

-- New profile = editable copy of the active one.
local function NewProfile()
	if #configs.profiles >= MAX_CUSTOM_PROFILES then
		return nil
	end
	local n = 1
	while FindProfile("custom" .. n) ~= nil do
		n = n + 1
	end
	local profile = Profiles.Copy(ActiveProfile(), "custom" .. n, string.format(STRINGS.BALATRO.TJ.CUSTOM_NAME, n))
	table.insert(configs.profiles, profile)
	configs.ai.profile = profile.id
	SaveConfigs()
	return profile
end

local function DeleteActiveProfile()
	local active = ActiveProfile()
	if active.preset then
		return false
	end
	for i, p in ipairs(configs.profiles) do
		if p.id == active.id then
			table.remove(configs.profiles, i)
			break
		end
	end
	configs.ai.profile = "balanced"
	SaveConfigs()
	return true
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

-- Expected value of a reward distribution under the active profile.
local function EVof(dist)
	return dist ~= nil and Profiles.EV(dist, Utility()) or nil
end

local function DistLine(dist)
	return string.format(STRINGS.BALATRO.TJ.ODDS, Pct(dist[1]), Pct(dist[6] + dist[7] + dist[8]), Pct(dist[8]), EVof(dist))
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
				local profile = ActiveProfile()
				for i = 1, 3 do
					if names[i] ~= nil then
						local best = advice ~= nil and advice.best == i
						local mark = best and "*" or ""
						table.insert(cols, {
							header = mark .. ShortName(names[i]),
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
		local summary = ProfileSummary(ActiveProfile(), RerollActive())
		table.insert(cols, { header = STRINGS.BALATRO.TJ.COL_AVG, dist = summary.play > 0 and summary.dist or nil, empty = true })
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
						cell:SetString(col.dist ~= nil and string.format("%.1f", EVof(col.dist)) or missing)
					end
				end
			end
		end
		local summary = ProfileSummary(ActiveProfile(), RerollActive())
		panel.subtitle:SetString(string.format(STRINGS.BALATRO.TJ.ODDS_SUBTITLE,
			ActiveProfile().name,
			OptionText(BUDGET_OPTIONS, configs.ai.budget),
			RerollActive() and STRINGS.BALATRO.TJ.ON or STRINGS.BALATRO.TJ.OFF))
		panel.footer:SetString(string.format(STRINGS.BALATRO.TJ.ODDS_FOOTER,
			Pct(summary.play), summary.play > 0 and summary.rerolls or 0, played, configs.stats.rerolls))
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

		local profile = ActiveProfile()
		local others = {}
		for i = 1, 3 do
			if i ~= best and names[i] ~= nil then
				local v = EVof(dists[i])
				table.insert(others, JokerDisplayName(names[i]) .. " " .. (v ~= nil and string.format("%.1f", v) or "?"))
			end
		end
		-- A start = hand + offered jokers; its EV is the best joker's EV.
		local best_ev = EVof(dists[best]) or values[best]
		local rule = ProfileSummary(profile, true)
		local weak = rule.threshold ~= nil and best_ev < rule.threshold
		local beats = Profiles.Percentile(profile, best_ev)
		self:TJ_SetText(string.format(STRINGS.BALATRO.TJ.JOKER_HINT, JokerDisplayName(names[best]), best_ev, Pct(beats)) .. "\n"
			.. (weak and string.format(STRINGS.BALATRO.TJ.WEAK_START, Pct(rule.share))
				or string.format(STRINGS.BALATRO.TJ.OTHERS, table.concat(others, ", "))))
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
		self:TJ_ShowProfile(false)
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
		self:TJ_ShowProfile(false)
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
		if self.TJ_SyncSettingWidgets ~= nil then
			self:TJ_SyncSettingWidgets()
		end
		if self.TJ_RefreshProfile ~= nil and not self.tj.refreshing then
			self:TJ_RefreshProfile()
		end
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
	ai_section.title:SetPosition(0, 32, 0)
	local function AddSpinner(label, options, key, y)
		local w = ai_section:AddChild(Templates.LabelSpinner(label, options, 180, 220, 30, 8, GLOBAL.CHATFONT_OUTLINE, 21))
		w:SetPosition(0, y, 0)
		w.spinner:SetSelected(configs.ai[key])
		w.spinner:SetOnChangedFn(function(data)
			configs.ai[key] = data
			SaveConfigs()
			self:TJ_OnSettingsChanged()
		end)
		return w
	end
	ai_section.profile = AddSpinner(STRINGS.BALATRO.TJ.SETTING_PROFILE, ProfileOptions(), "profile", 2)
	ai_section.budget = AddSpinner(STRINGS.BALATRO.TJ.SETTING_BUDGET, BUDGET_OPTIONS, "budget", -30)
	ai_section.reroll = AddSpinner(STRINGS.BALATRO.TJ.SETTING_REROLL, RerollShareOptions(), "reroll_share", -62)
	ai_section.edit = ai_section:AddChild(ImageButton("images/balatro.xml", "button_normal.tex", "button_focus.tex", "button_disabled.tex", "button_normal.tex", "button_focus.tex", { 0.7, 0.7, 0.7 }))
	ai_section.edit:SetPosition(0, -94, 0)
	ai_section.edit:SetScale(0.55)
	ai_section.edit:SetTextSize(25)
	ai_section.edit:SetNormalScale(0.7, 0.7, 0.7)
	ai_section.edit:SetFocusScale(0.75, 0.75, 0.75)
	ai_section.edit:SetText(STRINGS.BALATRO.TJ.BUTTON_PROFILES)
	ai_section.edit:SetOnClick(function()
		self:TJ_ShowProfile(true)
	end)

	-- Show `data` in a spinner without firing its change callback.
	local function SilentSelect(spinner, data, options)
		local fn = spinner.onchangedfn
		spinner:SetOnChangedFn(nil)
		if options ~= nil then
			spinner:SetOptions(options)
		end
		spinner:SetSelected(data)
		spinner:SetOnChangedFn(fn)
	end

	-- Keep every settings widget in sync (the reroll share is shown in two panels).
	function self:TJ_SyncSettingWidgets()
		SilentSelect(ai_section.profile.spinner, configs.ai.profile, ProfileOptions())
		SilentSelect(ai_section.reroll.spinner, configs.ai.reroll_share)
		if self.root.game_profile ~= nil then
			SilentSelect(self.root.game_profile.summary.reroll.spinner, configs.ai.reroll_share)
		end
	end
	self.TJ_RefreshProfileSpinner = self.TJ_SyncSettingWidgets
	ai_section.note = ai_section:AddChild(Text(GLOBAL.CHATFONT_OUTLINE, 15, STRINGS.BALATRO.TJ.SETTINGS_NOTE, GLOBAL.UICOLOURS.GOLD))
	ai_section.note:SetPosition(0, -121, 0)
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
			self:TJ_ShowProfile(false)
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

	----------------------------------------------------------------------------
	-- PROFILE panel: reward values, joker matrix with blocks, % to play + final odds
	----------------------------------------------------------------------------

	local TJ = STRINGS.BALATRO.TJ
	local DIM = { 0.55, 0.55, 0.55, 1 }
	local UTIL_OPTIONS = {}
	for _, v in ipairs(Profiles.UTILITY_VALUES) do
		table.insert(UTIL_OPTIONS, { text = Profiles.FormatValue(v), data = v })
	end
	local PAGE_OPTIONS = {
		{ text = TJ.PAGE_VALUES, data = 1 },
		{ text = TJ.PAGE_JOKERS_1, data = 2 },
		{ text = TJ.PAGE_JOKERS_2, data = 3 },
		{ text = TJ.PAGE_SUMMARY, data = 4 },
	}

	local function SmallText(parent, size, x, y, w, align, colour)
		local t = parent:AddChild(Text(GLOBAL.CHATFONT_OUTLINE, size, "", colour or GLOBAL.UICOLOURS.WHITE))
		t:SetRegionSize(w, size + 4)
		if align ~= nil then t:SetHAlign(align) end
		t:SetPosition(x, y, 0)
		return t
	end

	local function SmallButton(parent, label, x, y, onclick)
		local b = parent:AddChild(ImageButton("images/balatro.xml", "button_normal.tex", "button_focus.tex", "button_disabled.tex", "button_normal.tex", "button_focus.tex", { 0.7, 0.7, 0.7 }))
		b:SetPosition(x, y, 0)
		b:SetScale(0.5)
		b:SetTextSize(25)
		b:SetNormalScale(0.7, 0.7, 0.7)
		b:SetFocusScale(0.75, 0.75, 0.75)
		b:SetText(label)
		b:SetOnClick(onclick)
		return b
	end

	local pp = self.root:AddChild(UIAnim())
	self.root.game_profile = pp
	pp:GetAnimState():SetBuild("ui_balatro")
	pp:GetAnimState():SetBank("ui_balatro")
	pp:GetAnimState():PlayAnimation("green_idle", true)
	pp:SetPosition(150, -40, 0)
	pp:Hide()
	pp.showing = false
	pp.page = 1
	pp.title = pp:AddChild(Text(GLOBAL.CHATFONT_OUTLINE, 24, "", GLOBAL.UICOLOURS.GOLD))
	pp.title:SetPosition(0, 170, 0)
	pp.page_spinner = pp:AddChild(Templates.StandardSpinner(PAGE_OPTIONS, 300, 30, GLOBAL.CHATFONT_OUTLINE, 20, function(data)
		pp.page = data
		self:TJ_RefreshProfile()
	end))
	pp.page_spinner:SetPosition(0, 143, 0)

	-- Apply an edit to the active (custom) profile.
	function self:TJ_EditProfile(fn)
		if self.tj.refreshing then
			return
		end
		local profile = ActiveProfile()
		if not profile.preset then
			fn(profile)
			SaveConfigs()
			self:TJ_OnSettingsChanged()
		end
		self:TJ_RefreshProfile()
	end

	-- Page 1: utility value of every reward
	pp.values = pp:AddChild(Widget("tj_values"))
	pp.values.rows = {}
	for r = 1, 8 do
		local w = pp.values:AddChild(Templates.LabelSpinner(TJ.TIERS[r], UTIL_OPTIONS, 190, 170, 26, 8, GLOBAL.CHATFONT_OUTLINE, 19))
		w:SetPosition(0, 114 - 25 * (r - 1), 0)
		w.spinner:SetOnChangedFn(function(data)
			self:TJ_EditProfile(function(profile)
				profile.util[r] = data
			end)
		end)
		pp.values.rows[r] = w
	end
	pp.values.hint = pp.values:AddChild(Text(GLOBAL.CHATFONT_OUTLINE, 16, TJ.VALUES_HINT, GLOBAL.UICOLOURS.GOLD))
	pp.values.hint:SetPosition(0, -86, 0)
	pp.values.hint:SetRegionSize(460, 36)
	pp.values.hint:EnableWordWrap(true)

	-- Pages 2-3: joker matrix (sorted by EV, read-only) + how often the AI plays each joker
	local MX_NAME_X, MX_TIER_X0, MX_TIER_DX, MX_EV_X, MX_PICK_X = -205, -128, 35, 158, 212
	pp.matrix = pp:AddChild(Widget("tj_matrix"))
	local mh = SmallText(pp.matrix, 15, MX_NAME_X, 114, 76, GLOBAL.ANCHOR_LEFT, GLOBAL.UICOLOURS.GOLD)
	mh:SetString(TJ.COL_JOKER)
	for r = 1, 8 do
		SmallText(pp.matrix, 15, MX_TIER_X0 + MX_TIER_DX * (r - 1), 114, 36, nil, GLOBAL.UICOLOURS.GOLD):SetString(TJ.TIERS_SHORT[r])
	end
	SmallText(pp.matrix, 15, MX_EV_X, 114, 44, nil, GLOBAL.UICOLOURS.GOLD):SetString(TJ.COL_EV)
	SmallText(pp.matrix, 15, MX_PICK_X, 114, 46, nil, GLOBAL.UICOLOURS.GOLD):SetString(TJ.COL_PICK)
	pp.matrix.rows = {}
	for k = 1, 9 do
		local y = 92 - 22 * (k - 1)
		local row = {}
		row.name = SmallText(pp.matrix, 16, MX_NAME_X, y, 76, GLOBAL.ANCHOR_LEFT)
		row.cells = {}
		for r = 1, 8 do
			row.cells[r] = SmallText(pp.matrix, 16, MX_TIER_X0 + MX_TIER_DX * (r - 1), y, 36)
		end
		row.ev = SmallText(pp.matrix, 16, MX_EV_X, y, 44)
		row.pick = SmallText(pp.matrix, 16, MX_PICK_X, y, 46, nil, GLOBAL.UICOLOURS.GOLD)
		pp.matrix.rows[k] = row
	end

	-- Page 4: summary. The reroll share is the same global setting as in CONFIGS.
	pp.summary = pp:AddChild(Widget("tj_summary"))
	pp.summary.reroll = pp.summary:AddChild(Templates.LabelSpinner(TJ.SETTING_REROLL, RerollShareOptions(), 150, 230, 28, 8, GLOBAL.CHATFONT_OUTLINE, 19))
	pp.summary.reroll:SetPosition(0, 116, 0)
	pp.summary.reroll.spinner:SetSelected(configs.ai.reroll_share)
	pp.summary.reroll.spinner:SetOnChangedFn(function(data)
		if self.tj.refreshing then return end
		configs.ai.reroll_share = data
		SaveConfigs()
		self:TJ_OnSettingsChanged()
		self:TJ_RefreshProfile()
	end)
	local SUM_LABELS = { TJ.ROW_THRESHOLD, TJ.ROW_PLAY, TJ.ROW_REROLLS }
	for r = 1, 8 do SUM_LABELS[#SUM_LABELS + 1] = TJ.TIERS[r] end
	SUM_LABELS[#SUM_LABELS + 1] = TJ.ROW_EV_GAME
	SUM_LABELS[#SUM_LABELS + 1] = TJ.ROW_EV_MIN
	pp.summary.h1 = SmallText(pp.summary, 15, 55, 91, 110, nil, GLOBAL.UICOLOURS.GOLD)
	pp.summary.h1:SetString(TJ.COL_NO_REROLLS)
	pp.summary.h2 = SmallText(pp.summary, 15, 170, 91, 120, nil, GLOBAL.UICOLOURS.GOLD)
	pp.summary.rows = {}
	for i, label in ipairs(SUM_LABELS) do
		local y = 91 - 15 * i
		SmallText(pp.summary, 15, -140, y, 200, GLOBAL.ANCHOR_LEFT, GLOBAL.UICOLOURS.GOLD):SetString(label)
		pp.summary.rows[i] = { base = SmallText(pp.summary, 15, 55, y, 110), mine = SmallText(pp.summary, 15, 170, y, 120) }
	end

	-- Bottom buttons
	pp.new_btn = SmallButton(pp, TJ.BUTTON_NEW, -170, -124, function()
		if NewProfile() ~= nil then
			self:TJ_RefreshProfileSpinner()
			self:TJ_OnSettingsChanged()
			self:TJ_RefreshProfile()
		end
	end)
	pp.del_btn = SmallButton(pp, TJ.BUTTON_DELETE, -95, -124, function()
		if DeleteActiveProfile() then
			self:TJ_RefreshProfileSpinner()
			self:TJ_OnSettingsChanged()
			self:TJ_RefreshProfile()
		end
	end)
	pp.back_btn = SmallButton(pp, TJ.BUTTON_BACK, 205, -124, function()
		self:TJ_ShowProfile(false)
		self.root.game_configs:MoveToFront()
		self.root.game_configs:Show()
		self.root.game_configs.showing = true
	end)
	pp.status = pp:AddChild(Text(GLOBAL.CHATFONT_OUTLINE, 15, "", GLOBAL.UICOLOURS.GOLD))
	pp.status:SetPosition(55, -124, 0)
	pp.status:SetRegionSize(190, 36)
	pp.status:EnableWordWrap(true)

	function self:TJ_ShowProfile(show)
		if show then
			if self.root.game_notes.showing then
				self.root.game_notes:Hide()
				self.root.game_notes.showing = false
			end
			if self.root.game_configs.showing then
				self.root.game_configs:Hide()
				self.root.game_configs.showing = false
			end
			self:TJ_ShowOdds(false)
			pp:MoveToFront()
			pp:Show()
			pp.showing = true
			self:TJ_RefreshProfile()
		else
			pp:Hide()
			pp.showing = false
		end
	end

	function self:TJ_RefreshProfile()
		if not pp.showing then
			return
		end
		self.tj.refreshing = true
		local profile = ActiveProfile()
		local editable = not profile.preset
		local rows, res = Profiles.Matrix(profile, RerollShare())

		pp.title:SetString(string.format(editable and TJ.PROFILE_TITLE or TJ.PRESET_TITLE, profile.name))
		if editable then pp.del_btn:Enable() else pp.del_btn:Disable() end
		if #configs.profiles < MAX_CUSTOM_PROFILES then pp.new_btn:Enable() else pp.new_btn:Disable() end

		local page = pp.page
		if page == 1 then pp.values:Show() else pp.values:Hide() end
		if page == 2 or page == 3 then pp.matrix:Show() else pp.matrix:Hide() end
		if page == 4 then pp.summary:Show() else pp.summary:Hide() end

		if page == 4 then
			pp.status:SetString(string.format(TJ.TIME_NOTE, Profiles.SECONDS_PER_GAME, Profiles.SECONDS_PER_REROLL, Pct(res.auto_share)))
		else
			pp.status:SetString(editable and string.format(TJ.STATUS_EDITABLE, res.hands, res.style) or TJ.STATUS_PRESET)
		end

		if page == 1 then
			for r = 1, 8 do
				local spinner = pp.values.rows[r].spinner
				spinner:SetSelected(profile.util[r])
				if editable then spinner:Enable() else spinner:Disable() end
			end
		elseif page == 2 or page == 3 then
			local first = page == 2 and 0 or 9
			for k = 1, 9 do
				local row, data = pp.matrix.rows[k], rows[first + k]
				if data == nil then
					row.name:SetString("")
					for r = 1, 8 do row.cells[r]:SetString("") end
					row.ev:SetString("")
					row.pick:SetString("")
				else
					-- jokers the AI (almost) never plays are dimmed
					local colour = data.pick < 0.005 and DIM or GLOBAL.UICOLOURS.WHITE
					row.name:SetString(ShortName(data.joker))
					row.name:SetColour(colour)
					for r = 1, 8 do
						row.cells[r]:SetString(Pct(data.dist[r]))
						row.cells[r]:SetColour(colour)
					end
					row.ev:SetString(string.format("%.2f", data.ev))
					row.ev:SetColour(colour)
					row.pick:SetString(Pct(data.pick))
				end
			end
		elseif page == 4 then
			pp.summary.reroll.spinner:SetSelected(configs.ai.reroll_share)
			pp.summary.h2:SetString(res.share > 0 and string.format(TJ.COL_REROLL_WORST, Pct(res.share)) or TJ.COL_NO_REROLLS)
			local r = pp.summary.rows
			r[1].base:SetString("-")
			r[1].mine:SetString(res.threshold ~= nil and string.format("%.2f", res.threshold) or "-")
			r[2].base:SetString("100%")
			r[2].mine:SetString(Pct(res.play))
			r[3].base:SetString("0.00")
			r[3].mine:SetString(string.format("%.2f", res.rerolls))
			for t = 1, 8 do
				r[3 + t].base:SetString(Pct(res.base_dist[t]))
				r[3 + t].mine:SetString(Pct(res.dist[t]))
			end
			r[12].base:SetString(string.format("%.2f", res.base_ev))
			r[12].mine:SetString(string.format("%.2f", res.ev))
			r[13].base:SetString(string.format("%.2f", res.base_rate))
			r[13].mine:SetString(string.format("%.2f", res.rate))
		end
		self.tj.refreshing = false
	end

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
