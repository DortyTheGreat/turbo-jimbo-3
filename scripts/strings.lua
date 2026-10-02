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
	JOKER_HINT = "AI: %s  EV %.1f (beats %s of starts)",
	WEAK_START = "Among the worst %s of starts: reroll (free before picking)",
	OTHERS = "Others: %s",
	KEEP_ALL = "AI: keep everything",
	DISCARD_ALL = "AI: discard everything",
	DISCARD = "AI: discard %s",
	ODDS = "<120 %s   600+ %s   1400+ %s   EV %.1f",
	ON = "on",
	OFF = "off",

	-- CONFIGS panel
	SETTINGS_TITLE = "SMART AI",
	SETTING_PROFILE = "Profile:",
	SETTING_BUDGET = "Thinking:",
	SETTING_REROLL = "Reroll:",
	SHARE_NEVER = "never",
	SHARE_AUTO = "auto (best EV/min)",
	SHARE_WORST = "worst %d%%",
	BUTTON_PROFILES = "PROFILES",
	SETTINGS_NOTE = "Rerolls need Auto reroll + Autoplay + Replay. Smart AI off = joker ranking.",

	-- ODDS panel
	ODDS_TITLE = "REWARD ODDS",
	ODDS_SUBTITLE = "Profile: %s   Thinking: %s   Auto reroll: %s",
	ODDS_FOOTER = "*AI pick. Avg: long run with this profile (%s to play, %.2f rerolls/game). Played: your %d games, %d rerolls.",
	COL_REWARD = "Reward",
	COL_AI = "AI",
	COL_MARKED = "Marked",
	COL_AVG = "Avg",
	COL_PLAYED = "Played",
	ROW_LOOT = "EV",
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
	TIERS_SHORT = { "<120", "120", "150", "200", "400", "600", "1000", "1400" },

	-- PROFILE panel
	CUSTOM_NAME = "Custom %d",
	PROFILE_TITLE = "PROFILE: %s",
	PRESET_TITLE = "PROFILE: %s (preset)",
	STATUS_EDITABLE = "%d sample hands, %s-style play",
	STATUS_PRESET = "Preset, read-only. NEW makes an editable copy.",
	PAGE_VALUES = "1/4  Reward values",
	PAGE_JOKERS_1 = "2/4  Jokers: best 9",
	PAGE_JOKERS_2 = "3/4  Jokers: other 9",
	PAGE_SUMMARY = "4/4  Rerolls & summary",
	VALUES_HINT = "What each reward is worth to you. 0 = worth nothing, like a reroll. EV = sum of chance x value.",
	COL_JOKER = "Joker",
	COL_EV = "EV",
	COL_PICK = "Pick",
	ROW_THRESHOLD = "Reroll if start EV <",
	ROW_PLAY = "% to play",
	ROW_REROLLS = "Rerolls per game",
	ROW_EV_GAME = "EV per game",
	ROW_EV_MIN = "EV per minute*",
	COL_NO_REROLLS = "No rerolls",
	COL_REROLL_WORST = "Reroll worst %s",
	TIME_NOTE = "*~%ds per game, ~%ds per reroll. Best EV/min: worst %s",
	BUTTON_NEW = "NEW",
	BUTTON_DELETE = "DELETE",
	BUTTON_BACK = "BACK",
}
