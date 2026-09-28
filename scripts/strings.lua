local STRINGS = GLOBAL.STRINGS

STRINGS.BALATRO.BUTTON_CONFIGS = "CONFIGS"
STRINGS.BALATRO.CONFIGS_TURBO = "Turbo"
STRINGS.BALATRO.CONFIGS_REPLAY = "Replay"
STRINGS.BALATRO.CONFIGS_AUTOPLAY = "Autoplay"
STRINGS.BALATRO.CONFIGS_SKIP_ENDING = "Skip ending"
STRINGS.BALATRO.CONFIGS_REVEAL_CARDS = "Reveal cards"
STRINGS.BALATRO.CONFIGS_MACROS_END_ROUND = "Macros end round"
STRINGS.BALATRO.CONFIGS_SMART = "Smart AI"
STRINGS.BALATRO.CONFIGS_AUTO_REROLL = "Auto reroll"

STRINGS.BALATRO.CONFIGS_MOST_PREFERRED_TEXT = "<----- Most preferred"
STRINGS.BALATRO.CONFIGS_LEAST_PREFERRED_TEXT = "Least preferred ----->"

STRINGS.BALATRO.MACROS = {
	-- Using emojis was a pretty good idea to fit text into the bounds of buttons
	CHOOSE_JOKER = "PICK JOKER",
	KEEP_PAIRS = "KEEP PAIRS",
	KEEP_HEARTS = "KEEP 󰀍",
	KEEP_CLUBS = "KEEP 󰀋",
	KEEP_SPADES = "KEEP 󰀪",
	KEEP_KINGS = "KEEP K",
	KEEP_QUEENS = "KEEP Q",
	KEEP_FACES = "KEEP JQK",
	DISCARD_HEARTS = "DUMP 󰀍",
	DISCARD_HEARTS_AND_DIAMONDS = "DUMP 󰀍󰀧",
	DISCARD_FACES = "DUMP JQK",
	DISCARD_ALL = "DUMP ALL",
	-- Smart AI
	BEST_JOKER = "BEST JOKER",
	BEST_MOVE = "BEST MOVE",
	REROLL = "REROLL",
	ODDS = "ODDS",
}

-- Smart AI texts. %s / %d / %.1f are filled in by the mod, keep them.
STRINGS.BALATRO.TJ = {
	THINKING = "AI is thinking...",
	REROLLING = "Weak start, rerolling...",
	JOKER_HINT = "AI: %s (loot %.1f)  |  %s",
	WEAK_START = "Weak start: closing before picking a joker is free",
	KEEP_ALL = "AI: keep everything",
	DISCARD_ALL = "AI: discard everything",
	DISCARD = "AI: discard %s",
	ODDS = "<120 %s   600+ %s   1400+ %s   loot %.1f",

	-- CONFIGS panel
	SETTINGS_TITLE = "SMART AI",
	SETTING_GOAL = "Goal:",
	SETTING_BUDGET = "Thinking:",
	SETTING_REROLL = "Auto reroll if loot <",
	SETTINGS_NOTE = "Auto reroll needs Autoplay + Replay. Turn Smart AI off to edit the joker ranking.",
	OFF = "off",

	-- ODDS panel
	ODDS_TITLE = "REWARD ODDS",
	ODDS_SUBTITLE = "Goal: %s   Thinking: %s   Auto reroll: %s",
	ODDS_FOOTER = "*AI pick. Avg: per game in the long run with these settings (%.1f rerolls/game). Played: your %d games, %d rerolls.",
	COL_REWARD = "Reward",
	COL_AI = "AI",
	COL_MARKED = "Marked",
	COL_AVG = "Avg",
	COL_PLAYED = "Played",
	ROW_LOOT = "Loot value",
	TIERS = {
		"<120 Monsters",
		"120 Grass, twig",
		"150 Stone, rope",
		"200 Bananas",
		"400 Banana pops",
		"600 2 Gold",
		"1000 8 Gold",
		"1400 Gems, gold",
	},
}
