local ImageButton = require("widgets/imagebutton")
local Text = require("widgets/text")
local UIAnim = require("widgets/uianim")
local UIAnimButton = require("widgets/uianimbutton")
local Templates = require("widgets/redux/templates")
local PersistentData = require("persistentdata")
modimport("scripts/strings.lua")

-- Load saved data. Other mods can access this with persistentdata.
local ModData = PersistentData(modname)
ModData:Load()
local configs = ModData:GetValue("configs")
if not configs then
	configs = {
		checkboxes = {
			turbo = false,
			replay = false,
			autoplay = false,
			reveal_cards = false,
			macros_end_round = false,
		},
		jokers_rank = {
		[1] = "wendy",
		[2] = "wurt",
		[3] = "webber",
		[4] = "winona",
		[5] = "wilson",
		[6] = "wathgrithr",
		[7] = "waxwell",
		[8] = "walter",
		[9] = "wx78",
		[10] = "woodie",
		[11] = "warly",
		[12] = "wormwood",
		[13] = "wortox",
		[14] = "wolfgang",
		[15] = "wickerbottom",
		[16] = "willow",
		[17] = "wes",
		[18] = "wanda",
		},
	}
	ModData:SetValue("configs", configs)
	ModData:Save()
end
-- Define which macros to use for each button
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
		wurt = {
			[1] = "KEEP_FACES",
			[2] = nil,
		},
		wortox = {
			[1] = "KEEP_HEARTS",
			[2] = "DISCARD_HEARTS",
		},
		warly = {
			[1] = nil,
			[2] = nil,
		},
		winona = {
			[1] = "KEEP_HEARTS",
			[2] = nil,
		},
		wes = {
			[1] = nil,
			[2] = "DISCARD_ALL",
		},
		wendy = {
			[1] = nil,
			[2] = "DISCARD_ALL",
		},
		webber = {
			[1] = "DISCARD_HEARTS_AND_DIAMONDS",
			[2] = "DISCARD_ALL",
		},
		woodie = {
			[1] = nil,
			[2] = "DISCARD_ALL",
		},
		wolfgang = {
			[1] = "KEEP_KINGS",
			[2] = nil,
		},
		willow = {
			[1] = nil,
			[2] = "DISCARD_FACES",
		},
		wx78 = {
			[1] = "KEEP_HEARTS",
			[2] = "DISCARD_HEARTS",
		},
		wickerbottom = {
			[1] = "KEEP_QUEENS",
			[2] = nil,
		},
		waxwell = {
			[1] = nil,
			[2] = "DISCARD_HEARTS",
		},
		walter = {
			[1] = nil,
			[2] = "DISCARD_ALL",
		},
		wormwood = {
			[1] = "KEEP_CLUBS",
			[2] = nil,
		},
		wanda = {
			[1] = nil,
			[2] = nil,
		},
		wathgrithr = {
			[1] = "KEEP_SPADES",
			[2] = nil,
		},
		wilson = {
			[1] = "KEEP_PAIRS",
			[2] = nil,
		},
	},
}
local macro_defs = {
	CHOOSE_JOKER = function(self)
		local joker_choices = {}
		for joker_index=1, 3 do 
			joker_choices[self.root["joker_card"..joker_index].joker_selected.name] = joker_index
		end
		for rank, name  in ipairs(configs.jokers_rank) do
			if joker_choices[name] then
				self:SelectJoker(joker_choices[name])
				break
			end
		end
	end,
	SELECT_PAIRS = function(self)
		local seen_numbers = {[self:Num(1)]={1}}
		for card_index=2, 5 do
			if seen_numbers[self:Num(card_index)] then
				table.insert(seen_numbers[self:Num(card_index)],card_index)
			else
				seen_numbers[self:Num(card_index)]={card_index}
			end
		end
		for seen_number, cards in pairs(seen_numbers) do
			if #cards > 1 then
				for _, card_index in pairs(cards) do
					self:MarkForDiscard(card_index)
				end
			end
		end
	end,
	SELECT_SUIT = function(self, suit)
		for card_index=1, 5 do
			if self:Suit(card_index) == suit then
				self:MarkForDiscard(card_index)
			end
		end
	end,
	SELECT_NUM = function(self, num)
		for card_index=1, 5 do
			if self:Num(card_index) == num then
				self:MarkForDiscard(card_index)
			end
		end
	end,
	SELECT_ABOVE = function(self, threshold)
		for card_index=1, 5 do
			if self:Num(card_index) > threshold then
				self:MarkForDiscard(card_index)
			end
		end
	end,
	KEEP_ALL = function(self)
		for card_index=1, 5 do
			self:UnmarkForDiscard(card_index)
		end
	end,
	DISCARD_ALL = function(self)
		for card_index=1, 5 do
			self:MarkForDiscard(card_index)
		end
	end,
	INVERT_SELECTION = function(self)
		for card_index=1,5 do
			if self.discard[card_index] then
				self:UnmarkForDiscard(card_index)
			else
				self:MarkForDiscard(card_index)
			end
		end
	end,
}
macro_defs.SELECT_PAIRS_ABOVE = function(self, threshold)
	local seen_numbers = {[self:Num(1)]={1}}
	for card_index=2, 5 do
		if seen_numbers[self:Num(card_index)] then
			table.insert(seen_numbers[self:Num(card_index)],card_index)
		else
			seen_numbers[self:Num(card_index)]={card_index}
		end
	end
	for seen_number, cards in pairs(seen_numbers) do
		if seen_number > threshold and #cards > 1 then
			for _, card_index in pairs(cards) do
				self:MarkForDiscard(card_index)
			end
		end
	end
end
macro_defs.SELECT_ABOVE_WITH_ACE = function(self, threshold)
	for card_index=1, 5 do
		local card_num = self:Num(card_index)
		if card_num > threshold or (card_num == 1 and threshold < 11) then
			self:MarkForDiscard(card_index)
		end
	end
end
macro_defs.KEEP_PAIRS = function(self)
	macro_defs.KEEP_ALL(self)
	macro_defs.SELECT_PAIRS(self)
	macro_defs.INVERT_SELECTION(self)
end
macro_defs.KEEP_HEARTS = function(self)
	macro_defs.KEEP_ALL(self)
	macro_defs.SELECT_SUIT(self, SUITS.HEARTS)
	macro_defs.INVERT_SELECTION(self)
end
macro_defs.KEEP_CLUBS = function(self)
	macro_defs.KEEP_ALL(self)
	macro_defs.SELECT_SUIT(self, SUITS.CLUBS)
	macro_defs.INVERT_SELECTION(self)
end
macro_defs.KEEP_SPADES = function(self)
	macro_defs.KEEP_ALL(self)
	macro_defs.SELECT_SUIT(self, SUITS.SPADES)
	macro_defs.INVERT_SELECTION(self)
end
macro_defs.KEEP_FACES = function(self)
	macro_defs.KEEP_ALL(self)
	macro_defs.SELECT_ABOVE(self, 10)
	macro_defs.INVERT_SELECTION(self)
end
macro_defs.KEEP_HIGH = function(self)
	macro_defs.KEEP_ALL(self)
	macro_defs.SELECT_ABOVE_WITH_ACE(self, 7)
	macro_defs.INVERT_SELECTION(self)
end
macro_defs.KEEP_KINGS = function(self)
	macro_defs.KEEP_ALL(self)
	macro_defs.SELECT_NUM(self, 13)
	macro_defs.INVERT_SELECTION(self)
end
macro_defs.KEEP_QUEENS = function(self)
	macro_defs.KEEP_ALL(self)
	macro_defs.SELECT_NUM(self, 12)
	macro_defs.INVERT_SELECTION(self)
end
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

macro_defs.WURT = function(self)
	if round == 1 then
		macro_defs.DISCARD_FACES(self)
		macro_defs.SELECT_PAIRS_ABOVE(self, 4)
		macro_defs.INVERT_SELECTION(self)
	else
		macro_defs.KEEP_ALL(self)
		macro_defs.SELECT_ABOVE_WITH_ACE(self, 10)
		macro_defs.SELECT_PAIRS_ABOVE(self, 7)
		macro_defs.INVERT_SELECTION(self)
	end
end
macro_defs.WORTOX = function(self)
	-- Keeping a pair is safer than keeping a heart.
	macro_defs.KEEP_ALL(self)
	macro_defs.SELECT_SUIT(self, SUITS.HEARTS) -- All hearts selected
	macro_defs.INVERT_SELECTION(self) -- All non-hearts selected
	macro_defs.SELECT_PAIRS_ABOVE(self, 4) -- All non-hearts or pairs selected
	macro_defs.INVERT_SELECTION(self) -- Hearts AND non-pairs selected
end
macro_defs.WARLY = function(self)
	-- Discard lowest cards of each suit (but leave one)
	macro_defs.KEEP_ALL(self)
	local suit_tally = {}
	local card_suit, card_num
	for card_index=1, 5 do
		card_suit = self:Suit(card_index)
		if suit_tally[card_suit] then
			table.insert(suit_tally[card_suit].cards, card_index)
			card_num = self:Num(card_index)
			suit_tally[card_suit].max_num = math.max(suit_tally[card_suit].max_num, (card_num == 1 and 11) or card_num)
		else
			suit_tally[card_suit] = {cards={card_index}, max_num=self:Num(card_index)}
		end
	end
	for suit, suit_data in pairs(suit_tally) do
		for _, card_index in pairs(suit_data.cards) do
			card_num = self:Num(card_index)
			if ((card_num == 1 and 11) or card_num) < suit_data.max_num and card_num < 9 then
				self:MarkForDiscard(card_index)
			end
		end
	end
end
macro_defs.WINONA = function(self)
	if round == 1 then
		macro_defs.DISCARD_HEARTS(self)
		macro_defs.SELECT_ABOVE_WITH_ACE(self, 9)
		macro_defs.INVERT_SELECTION(self)
	else
		local num_hearts = 0
		for i=1, 5 do
			if self:Suit(i) == SUITS.HEARTS then
				num_hearts = num_hearts+1
			end
		end
		if num_hearts + self.mult < 1 then
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
end
macro_defs.WES = function(self)
	-- Low on mults most of the time. Keep pairs
	if round == 1 then
		macro_defs.KEEP_ALL(self)
		macro_defs.SELECT_ABOVE_WITH_ACE(self, 8)
		macro_defs.SELECT_PAIRS_ABOVE(self, 4)
		macro_defs.INVERT_SELECTION(self)
	else
		macro_defs.KEEP_ALL(self)
		macro_defs.SELECT_ABOVE_WITH_ACE(self, 7)
		macro_defs.SELECT_PAIRS_ABOVE(self, 4)
		macro_defs.INVERT_SELECTION(self)
	end
end
macro_defs.WENDY = function(self)
	if self.round == 1 then
		macro_defs.DISCARD_ALL(self)
	else
		if self.mult < 1 then
			macro_defs.WES(self)
		else
			macro_defs.KEEP_HIGH(self)
		end
	end
end
macro_defs.WEBBER = function(self)
	if self.round == 1 then
		macro_defs.KEEP_ALL(self)
		macro_defs.SELECT_ABOVE_WITH_ACE(self, 11)
		macro_defs.INVERT_SELECTION(self)
	else
		-- No point discarding spades and clubs second round
		macro_defs.KEEP_ALL(self)
		macro_defs.SELECT_ABOVE_WITH_ACE(self, 9)
		macro_defs.SELECT_PAIRS_ABOVE(self, 4)
		macro_defs.INVERT_SELECTION(self)
	end
end
macro_defs.WOODIE = function(self)
	if round == 1 then
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
		for card_index=1, 5 do
			if self.notdiscarded[i] then
				self:MarkForDiscard(card_index)
			end
		end
	end
end
macro_defs.WICKERBOTTOM = macro_defs.WES -- Might actually have mult if a queen shows up. Can safely discard pairs?
macro_defs.WAXWELL = function(self)
	if self.round == 1 then
		macro_defs.KEEP_ALL(self)
		macro_defs.SELECT_ABOVE_WITH_ACE(self, 9)
		macro_defs.INVERT_SELECTION(self)
	else
		local num_hearts = 0
		for i=1, 5 do
			if self:Suit(i) == SUITS.HEARTS then
				num_hearts = num_hearts+1
			end
		end
		if num_hearts + self.mult < 1 then
			macro_defs.WES(self)
		else
			macro_defs.KEEP_ALL(self)
			macro_defs.SELECT_ABOVE_WITH_ACE(self, 9) -- Highs selected
			macro_defs.INVERT_SELECTION(self) -- Lows selected
			macro_defs.SELECT_SUIT(self, SUITS.HEARTS) -- Lows or hearts selected
		end
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
	if round == 1 then
		-- Keep clubs and pairs
		macro_defs.KEEP_ALL(self)
		macro_defs.SELECT_SUIT(self, SUITS.CLUBS)
		macro_defs.SELECT_PAIRS_ABOVE(self, 4)
		macro_defs.INVERT_SELECTION(self)
	else
		macro_defs.KEEP_ALL(self)
		macro_defs.SELECT_SUIT(self, SUITS.CLUBS)
		macro_defs.SELECT_PAIRS_ABOVE(self, 4)
		macro_defs.SELECT_ABOVE_WITH_ACE(self, 10)
		macro_defs.INVERT_SELECTION(self)
	end
end
macro_defs.WANDA = function(self)
	-- Discarding is bad
	local seen_numbers = {[self:Num(1)]={1}}
	for card_index=2, 5 do
		if seen_numbers[self:Num(card_index)] then
			table.insert(seen_numbers[self:Num(card_index)],card_index)
		else
			seen_numbers[self:Num(card_index)]={card_index}
		end
	end
	for seen_number, cards in pairs(seen_numbers) do
		if #cards > 1 then
			macro_defs.KEEP_ALL(self)
			return
		end
	end
	macro_defs.KEEP_HIGH(self)
end
macro_defs.WATHGRITHR = function(self)
	-- Keep spades and pairs
	macro_defs.KEEP_ALL(self)
	macro_defs.SELECT_SUIT(self, SUITS.SPADES)
	macro_defs.SELECT_PAIRS_ABOVE(self, 4)
	macro_defs.INVERT_SELECTION(self)
end
macro_defs.WILSON = function(self)
	if round == 1 then
		-- Keep clubs and pairs
		macro_defs.KEEP_ALL(self)
		macro_defs.SELECT_ABOVE_WITH_ACE(self, 10)
		macro_defs.SELECT_PAIRS_ABOVE(self, 4)
		macro_defs.INVERT_SELECTION(self)
	else
		macro_defs.KEEP_ALL(self)
		local seen_numbers, card_num, max_num = {[self:Num(1)]={1}}, 0, 0
		for card_index=2, 5 do
			card_num = self:Num(card_index)
			if seen_numbers[card_num] then
				table.insert(seen_numbers[card_num],card_index)
			else
				seen_numbers[card_num]={card_index}
			end
			max_num = math.max(max_num, card_num)
		end
		for seen_number, cards in pairs(seen_numbers) do
			if #cards > 1 then -- Got at least 1 pair
				macro_defs.SELECT_ABOVE_WITH_ACE(self, 10)
				for _, card_index in pairs(cards) do
					self:MarkForDiscard(card_index)
				end
				macro_defs.INVERT_SELECTION(self)
				return
			end
		end
		macro_defs.SELECT_ABOVE_WITH_ACE(self, 11)
		macro_defs.INVERT_SELECTION(self)
	end
end

AddClassPostConstruct("widgets/redux/balatrowidget", function(self)
	-- Process a queue item on every single frame instead of waiting for the delay.
	local _OnUpdate = self.OnUpdate
	self.OnUpdate = function(...)
		if #self.queue > 0 then
			if configs.checkboxes.turbo and self.queue[1].time >= 0 then
				self.queue[1].time = 0
			end
		end

		_OnUpdate(...)
	end
	
	local _TryToCloseWithAnimations = self.parentscreen.TryToCloseWithAnimations
	self.parentscreen.TryToCloseWithAnimations = function(...)
		if self.root.machine:GetAnimState():IsCurrentAnimation("confetti") and configs.checkboxes.turbo and not configs.checkboxes.skip_ending then
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
	
	-- Add checks here to stop checking everywhere else. I can't believe Klei didn't put these checks here.
	local _MarkForDiscard = self.MarkForDiscard
	self.MarkForDiscard = function(self, card_index)
		if not self.discard[card_index] then
			if self.halt_card_update then
				self.discard[card_index] = true
			else
				_MarkForDiscard(self, card_index)
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
			end
		end
	end
	
	-- Rearrange existing buttons to fit configs button
	self.root.notes:SetScale(0.66)
	self.root.notes:SetPosition(14,-220,0)
	
	self.root.deal:SetScale(0.66)
	self.root.deal:SetPosition(195,-220,0)
	
	self.root.close:SetScale(0.66)
	self.root.close:SetPosition(286,-220,0)
	
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
    end)
	
	-- Create the configs button
	self.root.configs = self.root:AddChild(ImageButton("images/balatro.xml", "button_normal.tex",  "button_focus.tex", "button_disabled.tex", "button_normal.tex", "button_focus.tex",{0.7,0.7,0.7}))
	self.root.configs:SetPosition(105,-220,0)
    self.root.configs:SetScale(0.66)
    self.root.configs:SetTextSize(25)
    self.root.configs:SetNormalScale(0.7,0.7,0.7)
    self.root.configs:SetFocusScale(0.75,0.75,0.75)
    self.root.configs:SetText(GLOBAL.STRINGS.BALATRO.BUTTON_CONFIGS)
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
    end)
	
	-- Create the configs screen
	self.root.game_configs = self.root:AddChild(UIAnim())
	local game_configs_anim_state = self.root.game_configs:GetAnimState()
    game_configs_anim_state:SetBuild("ui_balatro")
    game_configs_anim_state:SetBank("ui_balatro")
    game_configs_anim_state:PlayAnimation("green_idle", true)
    self.root.game_configs:SetPosition(150,-40,0)
    self.root.game_configs:Hide()
	
	-- Create the configs checkboxes.
	-- Could iterate over the table instead but I might want to customize those in the future
	self.root.game_configs.turbo_checkbox = self.root.game_configs:AddChild(Templates.LabelCheckbox(function(checkbox)
		configs.checkboxes.turbo = not configs.checkboxes.turbo
		checkbox.checked = configs.checkboxes.turbo
		ModData:SetValue("configs", configs)
		ModData:Save()
		checkbox:Refresh()
	end, configs.checkboxes.turbo, GLOBAL.STRINGS.BALATRO.CONFIGS_TURBO))
	self.root.game_configs.turbo_checkbox:SetPosition(-180,160,0)
	self.root.game_configs.replay_checkbox = self.root.game_configs:AddChild(Templates.LabelCheckbox(function(checkbox)
		configs.checkboxes.replay = not configs.checkboxes.replay
		checkbox.checked = configs.checkboxes.replay
		ModData:SetValue("configs", configs)
		ModData:Save()
		checkbox:Refresh()
	end, configs.checkboxes.replay, GLOBAL.STRINGS.BALATRO.CONFIGS_REPLAY))
	self.root.game_configs.replay_checkbox:SetPosition(-180,125,0)
	self.root.game_configs.autoplay_checkbox = self.root.game_configs:AddChild(Templates.LabelCheckbox(function(checkbox)
		configs.checkboxes.autoplay = not configs.checkboxes.autoplay
		checkbox.checked = configs.checkboxes.autoplay
		ModData:SetValue("configs", configs)
		ModData:Save()
		checkbox:Refresh()
		if configs.checkboxes.autoplay then
			-- Disable macros if autoplay is enabled during round, but do not enable if autoplay is turned off
			self:EnableMacros(false)
		end
	end, configs.checkboxes.autoplay, GLOBAL.STRINGS.BALATRO.CONFIGS_AUTOPLAY))
	self.root.game_configs.autoplay_checkbox:SetPosition(-180,90,0)
	self.root.game_configs.reveal_cards_checkbox = self.root.game_configs:AddChild(Templates.LabelCheckbox(function(checkbox)
		configs.checkboxes.reveal_cards = not configs.checkboxes.reveal_cards
		checkbox.checked = configs.checkboxes.reveal_cards
		ModData:SetValue("configs", configs)
		ModData:Save()
		checkbox:Refresh()
	end, configs.checkboxes.reveal_cards, GLOBAL.STRINGS.BALATRO.CONFIGS_REVEAL_CARDS))
	self.root.game_configs.reveal_cards_checkbox:SetPosition(0,160,0)
	self.root.game_configs.macros_end_round_checkbox = self.root.game_configs:AddChild(Templates.LabelCheckbox(function(checkbox)
		configs.checkboxes.macros_end_round = not configs.checkboxes.macros_end_round
		checkbox.checked = configs.checkboxes.macros_end_round
		ModData:SetValue("configs", configs)
		ModData:Save()
		checkbox:Refresh()
	end, configs.checkboxes.macros_end_round, GLOBAL.STRINGS.BALATRO.CONFIGS_MACROS_END_ROUND))
	self.root.game_configs.macros_end_round_checkbox:SetPosition(0,125,0)
	self.root.game_configs.skip_ending_checkbox = self.root.game_configs:AddChild(Templates.LabelCheckbox(function(checkbox)
		configs.checkboxes.skip_ending = not configs.checkboxes.skip_ending
		checkbox.checked = configs.checkboxes.skip_ending
		ModData:SetValue("configs", configs)
		ModData:Save()
		checkbox:Refresh()
	end, configs.checkboxes.skip_ending, GLOBAL.STRINGS.BALATRO.CONFIGS_SKIP_ENDING))
	self.root.game_configs.skip_ending_checkbox:SetPosition(0,90,0)
	
	-- Create the jokers ranking
	-- Ranks start fromm . Lower number: More preferable
	self.root.game_configs.joker_rank_cards = {}
	for rank, name in ipairs(configs.jokers_rank) do
		self.root.game_configs.joker_rank_cards[rank] = self.root.game_configs:AddChild(UIAnimButton("balatro_machine", "balatro_machine", "card_idle", "card_idle", "card_idle", "card_idle", "card_idle"))
		local card = self.root.game_configs.joker_rank_cards[rank]
		card.rank = rank
		
		function card.UpdateCardArt(this_card)
			this_card.uianim:GetAnimState():OverrideSymbol("swap_card1", "balatro_jokers", "joker_"..configs.jokers_rank[this_card.rank])
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
			card:SetPosition(-225+45*rank,-11,0)
		else
			-- card:SetPosition(-225+45*(rank-9),-72,0)
			card:SetPosition(-630+45*rank,-72,0)
		end
		
        card:SetOnClick(function()
			if self.root.game_configs.selected_joker then
				if self.root.game_configs.selected_joker ~= card then
					-- Swap selected cards and save preference
					local selected = self.root.game_configs.selected_joker
					local card_name = configs.jokers_rank[card.rank]
					configs.jokers_rank[card.rank] = configs.jokers_rank[selected.rank]
					configs.jokers_rank[selected.rank] = card_name
					ModData:SetValue("configs", configs)
					ModData:Save()
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
	self.root.game_configs.most_preferred_text = self.root.game_configs:AddChild(Text(GLOBAL.CHATFONT_OUTLINE, 25, "", GLOBAL.UICOLOURS.GOLD))
	self.root.game_configs.most_preferred_text:SetString(GLOBAL.STRINGS.BALATRO.CONFIGS_MOST_PREFERRED_TEXT)
    self.root.game_configs.most_preferred_text:SetPosition(-90,35,0)
    self.root.game_configs.most_preferred_text:SetHAlign(GLOBAL.ANCHOR_LEFT)
	
	self.root.game_configs.least_preferred_text = self.root.game_configs:AddChild(Text(GLOBAL.CHATFONT_OUTLINE, 25, "", GLOBAL.UICOLOURS.GOLD))
	self.root.game_configs.least_preferred_text:SetString(GLOBAL.STRINGS.BALATRO.CONFIGS_LEAST_PREFERRED_TEXT)
    self.root.game_configs.least_preferred_text:SetPosition(90,-116,0)
    self.root.game_configs.least_preferred_text:SetHAlign(GLOBAL.ANCHOR_RIGHT)
	
	-- Define what macros do
	self.SUITS = SUITS
	self.root.macro_tree = macro_tree
	self.root.macro_defs = macro_defs
	function self:Suit(card_index)
		return math.floor(self.slots[card_index]/100)
	end
	function self:Num(card_index)
		return self.slots[card_index]%100
	end
	
	-- Create the macro buttons
	for macro_index=1, 2 do
		self.root["macro"..macro_index] = self.root:AddChild(ImageButton("images/balatro.xml", "button_normal.tex",  "button_focus.tex", "button_disabled.tex", "button_normal.tex", "button_focus.tex",{0.7,0.7,0.7}))
		local macro = self.root["macro"..macro_index]
		macro:SetScale(0.66)
		macro:SetTextSize(25)
		macro:SetNormalScale(0.7,0.7,0.7)
		macro:SetFocusScale(0.75,0.75,0.75)
		function macro.Update(this_macro, set)
			local macro_name = self.root.macro_tree[self.mode][macro_index]
			if self.mode == "deal" then
				macro_name = self.root.macro_tree[self.mode][self.joker][macro_index]
			end
			if macro_name then
				this_macro:SetOnClick(function()
					self.root.macro_defs[macro_name](self)
					if configs.checkboxes.macros_end_round then
						self.root.deal.onclick()
					end
				end)
				this_macro:SetText(GLOBAL.STRINGS.BALATRO.MACROS[macro_name] or "")
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
	self.root.macro1:SetPosition(195,-270,0)
	self.root.macro2:SetPosition(286,-270,0)
	
	-- AutoPlay wrapper
	function self:AutoPlay()
		if self.mode == "joker" then
			self.root.macro_defs.CHOOSE_JOKER(self)
			self:choose()
		elseif self.mode == "deal" then
			self.halt_card_update = true
			self.root.macro_defs[string.upper(self.joker)](self)
			self.halt_card_update = false
			for card_index=1, 5 do
				if self.discard[card_index] then
					self:MarkForDiscard(card_index)
				else
					self:UnmarkForDiscard(card_index)
				end
			end
			self:Deal()
		end
	end
	
	-- Update macros for each stage of the game
	function self:EnableMacros(set)
		self.root.macro1:Update(set)
		self.root.macro2:Update(set)
	end
	self:EnableMacros(not configs.checkboxes.autoplay)
	
	local _EnableDealButton = self.EnableDealButton
	self.EnableDealButton = function(self, set)
		if configs.checkboxes.skip_ending and self.round >= 3 then
			self.parentscreen:TryToCloseWithAnimations()
		end
		_EnableDealButton(self, set)
		if configs.checkboxes.autoplay then
			if set then self:AutoPlay() end
		else
			self:EnableMacros(set)
		end
	end
	
	-- Reveal cards at the start (simutaneously)
	-- print(self.slots[card_index])
	if configs.checkboxes.reveal_cards then
		table.insert(self.queue,{time=3*GLOBAL.FRAMES, fn=function()
			for card_index=1, 5 do
				self.root.machine["card"..card_index].uianim:GetAnimState():PlayAnimation("card_flip")
				GLOBAL.TheFrontEnd:GetSound():PlaySound("balatro/balatro_cabinet/cards_flip_HUD")
			end
		end})
		table.insert(self.queue,{time=6*GLOBAL.FRAMES, fn=function()
			for card_index=1, 5 do
				self:UpdateCardArt(card_index)
			end
		end})
	end
	
	-- Initiate autoplay
	if configs.checkboxes.autoplay then self:AutoPlay() end
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
-- GLOBAL.ThePlayer:ListenForEvent("ms_closepopups", function(self) end)
local _POPUPS_BALATRO_Close = GLOBAL.POPUPS.BALATRO.Close
GLOBAL.POPUPS.BALATRO.Close = function(self, inst, target, ...)
	_POPUPS_BALATRO_Close(self, inst, target, ...)
	-- Check if player exists and whether replay is already queued
	if inst ~= nil and not (inst.balatro_replay_task and inst.balatro_replay_task.fn) and configs.checkboxes.replay then
		inst.balatro_replay_task = inst:DoPeriodicTask(GLOBAL.FRAMES, function(inst)
			-- Check if machine still exists and replay is still on, otherwise cancel queue
			if inst.balatro_machine ~= nil and configs.checkboxes.replay then
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
							local x,y,z = inst.Transform:GetWorldPosition()
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