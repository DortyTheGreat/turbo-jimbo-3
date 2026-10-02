--[[
Turbo JIMBO profiles.

A profile = the value (utility) of each of the 8 rewards. 0 means "worth nothing",
the same as a reroll; monsters are usually negative.

A START CONFIGURATION is the starting hand + the 3 offered jokers. Its EV under a profile
is the EV of the best joker for that hand. Rerolling costs time, so the reroll rule is:
"reroll the worst X% of start configurations". This module computes, instantly:
  * the distribution of start EVs (and so the EV threshold of the worst X%),
  * % to play, rerolls per game, final reward odds, EV per game and EV per minute,
  * "Auto": the X with the best EV per minute,
  * an informative joker matrix (average odds, EV, how often the AI picks it).

It uses reference data (scripts/turbojimbo_refdata.lua) generated offline: for a few
hundred random starting hands, the outcome distribution of EVERY joker played by the
Smart AI, in 3 play styles. For each hand, all 816 possible joker offers are counted
exactly: a joker ranked k-th for that hand is the best offer in C(18-k, 2) of them.

Pure Lua 5.1, no game dependencies.
]]

local Brain = require("turbojimbo_brain")
local Ref = require("turbojimbo_refdata")

local P = {}

local NJ = #Brain.JOKER_NAMES
P.JOKERS = Brain.JOKER_NAMES
P.HANDS = Ref.N

-- Rough durations (seconds) from the machine's timers: a played game with turbo and its
-- reward sequence, vs closing + reopening before picking a joker.
P.SECONDS_PER_GAME = 12
P.SECONDS_PER_REROLL = 5
P.MAX_REROLL_SHARE = 0.9

P.PRESETS = {
	{ id = "balanced", name = "Balanced", style = "balanced", util = Brain.PROFILES.balanced, preset = true },
	{ id = "jackpot", name = "Jackpot", style = "jackpot", util = Brain.PROFILES.jackpot, preset = true },
	{ id = "safe", name = "Safe", style = "safe", util = Brain.PROFILES.safe, preset = true },
}

-- Values offered by the utility editor.
P.UTILITY_VALUES = {
	-100, -50, -30, -25, -20, -15, -10, -8, -6, -5, -4, -3, -2, -1.5, -1, -0.5, -0.2, -0.1,
	0, 0.05, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.8, 1, 1.2, 1.5, 2, 2.5, 3, 4, 5, 6, 8, 9, 10,
	12, 15, 18, 20, 22, 25, 30, 40, 50, 100,
}
-- "Reroll the worst X%" options. "auto" = best EV per minute.
P.REROLL_SHARES = { 0, "auto", 5, 10, 15, 20, 25, 30, 35, 40, 50, 60, 70, 80, 90 }

--------------------------------------------------------------------------------
-- Reference data decoding (2 base64 chars per probability, sqrt-quantized)
--------------------------------------------------------------------------------

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local DEC = {}
for i = 1, 64 do DEC[string.byte(B64, i)] = i - 1 end

local cache = {}
-- Flat array: ((h-1)*NJ + (j-1))*8 + r
local function StyleData(style)
	if cache[style] then return cache[style] end
	local rows = Ref.styles[style] or Ref.styles.balanced
	local D, byte = {}, string.byte
	for h = 1, Ref.N do
		local s = rows[h]
		for j = 1, NJ do
			local base = ((h - 1) * NJ + (j - 1)) * 8
			local sum = 0
			for r = 1, 8 do
				local pos = (((j - 1) * 8) + (r - 1)) * 2 + 1
				local q = DEC[byte(s, pos)] * 64 + DEC[byte(s, pos + 1)]
				local p = (q / 4095) ^ 2
				D[base + r] = p
				sum = sum + p
			end
			if sum > 0 then
				for r = 1, 8 do D[base + r] = D[base + r] / sum end
			end
		end
	end
	cache[style] = D
	return D
end

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function C2(n) return n >= 2 and n * (n - 1) / 2 or 0 end
local TRIPLES = NJ * (NJ - 1) * (NJ - 2) / 6

local function EV(dist, util)
	local v = 0
	for r = 1, 8 do v = v + dist[r] * util[r] end
	return v
end
P.EV = EV

-- Which reference play style best fits a profile's utility values.
local style_cache = {}
function P.StyleFor(profile)
	if profile.style then return profile.style end
	local key = table.concat(profile.util, ",")
	if style_cache[key] then return style_cache[key] end
	local best, bestv = "balanced", -math.huge
	for _, style in ipairs({ "balanced", "jackpot", "safe" }) do
		local D, total = StyleData(style), 0
		for i = 0, Ref.N * NJ - 1 do
			local b = i * 8
			for r = 1, 8 do total = total + D[b + r] * profile.util[r] end
		end
		if total > bestv then best, bestv = style, total end
	end
	style_cache[key] = best
	return best
end

--------------------------------------------------------------------------------
-- Distribution of start-configuration EVs
--------------------------------------------------------------------------------

-- Analysis of one utility vector (cached). Entries = (hand, joker) pairs that are the best
-- offer in at least one triple, sorted by EV ascending, with cumulative sums.
local analysis_cache, analysis_count = {}, 0
function P.Analyze(profile)
	local util = profile.util
	local style = P.StyleFor(profile)
	local key = style .. "|" .. table.concat(util, ",")
	if analysis_cache[key] then return analysis_cache[key] end

	local D = StyleData(style)
	local N = Ref.N
	local entries = {}
	local mean = {}
	for j = 1, NJ do mean[j] = { 0, 0, 0, 0, 0, 0, 0, 0 } end
	local ev, order = {}, {}
	for h = 1, N do
		for j = 1, NJ do
			local b = ((h - 1) * NJ + (j - 1)) * 8
			local v, m = 0, mean[j]
			for r = 1, 8 do
				local p = D[b + r]
				v = v + p * util[r]
				m[r] = m[r] + p
			end
			ev[j] = v
			order[j] = j
		end
		table.sort(order, function(x, y) return ev[x] > ev[y] end)
		for k = 1, NJ - 2 do
			local j = order[k]
			entries[#entries + 1] = { ev = ev[j], w = C2(NJ - k), j = j, b = ((h - 1) * NJ + (j - 1)) * 8 }
		end
	end
	table.sort(entries, function(x, y) return x.ev < y.ev end)

	-- prefix sums (index 0 = nothing rerolled)
	local M = #entries
	local cw, cev, cd = { [0] = 0 }, { [0] = 0 }, {}
	for r = 1, 8 do cd[r] = { [0] = 0 } end
	for i = 1, M do
		local e = entries[i]
		cw[i] = cw[i - 1] + e.w
		cev[i] = cev[i - 1] + e.w * e.ev
		for r = 1, 8 do cd[r][i] = cd[r][i - 1] + e.w * D[e.b + r] end
	end

	local rows = {}
	for j = 1, NJ do
		for r = 1, 8 do mean[j][r] = mean[j][r] / N end
		rows[j] = { joker = P.JOKERS[j], dist = mean[j], ev = EV(mean[j], util) }
	end

	local A = { style = style, util = util, hands = N, entries = entries, M = M, D = D,
		W = cw[M], cw = cw, cev = cev, cd = cd, rows = rows }

	-- Best EV per minute over all cut points (reroll entries 1..i).
	local best_i, best_rate = 0, -math.huge
	for i = 0, M do
		local p = 1 - cw[i] / A.W
		if 1 - p > P.MAX_REROLL_SHARE + 1e-9 then break end
		local rate = 60 * ((cev[M] - cev[i]) / A.W) / (p * P.SECONDS_PER_GAME + (1 - p) * P.SECONDS_PER_REROLL)
		if rate > best_rate + 1e-12 then best_i, best_rate = i, rate end
	end
	A.auto_cut = best_i

	analysis_count = analysis_count + 1
	if analysis_count > 24 then analysis_cache, analysis_count = {}, 0 end
	analysis_cache[key] = A
	return A
end

-- Cut index for "reroll the worst `share` (0..1)": as many lowest-EV entries as fit.
local function CutFor(A, share)
	if share == "auto" then return A.auto_cut end
	local target = share * A.W
	local lo, hi = 0, A.M
	while lo < hi do
		local mid = math.floor((lo + hi + 1) / 2)
		if A.cw[mid] <= target + 1e-9 then lo = mid else hi = mid - 1 end
	end
	return lo
end

-- share: 0..1 or "auto". Returns the summary for "reroll the worst share of starts".
function P.Summary(profile, share)
	local A = P.Analyze(profile)
	local i = CutFor(A, share)
	local M, W = A.M, A.W
	local res = { style = A.style, hands = A.hands, rows = A.rows }
	local played = W - A.cw[i]
	res.share = A.cw[i] / W
	res.play = played / W
	res.rerolls = res.play > 0 and (1 - res.play) / res.play or math.huge
	-- reroll if EV < threshold (nil = never)
	res.threshold = i > 0 and (i < M and A.entries[i + 1].ev or math.huge) or nil
	res.dist = {}
	for r = 1, 8 do res.dist[r] = played > 0 and (A.cd[r][M] - A.cd[r][i]) / played or 0 end
	res.ev = played > 0 and (A.cev[M] - A.cev[i]) / played or 0
	res.rate = 60 * ((A.cev[M] - A.cev[i]) / W) / (res.play * P.SECONDS_PER_GAME + (1 - res.play) * P.SECONDS_PER_REROLL)
	res.base_dist = {}
	for r = 1, 8 do res.base_dist[r] = A.cd[r][M] / W end
	res.base_ev = A.cev[M] / W
	res.base_rate = 60 * res.base_ev / P.SECONDS_PER_GAME
	res.auto_share = A.cw[A.auto_cut] / W
	-- how often each joker is played, among played starts
	local picks = {}
	for j = 1, NJ do picks[j] = 0 end
	for k = i + 1, M do
		local e = A.entries[k]
		picks[e.j] = picks[e.j] + e.w
	end
	res.pick = {}
	for j = 1, NJ do res.pick[P.JOKERS[j]] = played > 0 and picks[j] / played or 0 end
	return res
end

-- Fraction of start configurations with a lower EV than `ev` (0..1).
function P.Percentile(profile, ev)
	local A = P.Analyze(profile)
	local lo, hi = 0, A.M
	while lo < hi do
		local mid = math.floor((lo + hi + 1) / 2)
		if A.entries[mid].ev < ev then lo = mid else hi = mid - 1 end
	end
	return A.cw[lo] / A.W
end

-- Matrix rows (all 18 jokers) sorted by EV, with pick rates for `share`.
function P.Matrix(profile, share)
	local res = P.Summary(profile, share)
	local rows = {}
	for _, row in ipairs(res.rows) do
		rows[#rows + 1] = { joker = row.joker, dist = row.dist, ev = row.ev, pick = res.pick[row.joker] }
	end
	table.sort(rows, function(a, b) return a.ev > b.ev end)
	return rows, res
end

--------------------------------------------------------------------------------
-- Profile objects
--------------------------------------------------------------------------------

function P.Copy(profile, id, name)
	local util = {}
	for r = 1, 8 do util[r] = profile.util[r] end
	return { id = id, name = name, util = util }
end

-- Make a saved custom profile safe to use (old/corrupt saves; v0.7 blocks are dropped).
function P.Sanitize(profile)
	if type(profile) ~= "table" or type(profile.id) ~= "string" then return nil end
	local util = {}
	for r = 1, 8 do
		util[r] = type(profile.util) == "table" and tonumber(profile.util[r]) or nil
		if util[r] == nil then util[r] = Brain.PROFILES.balanced[r] end
	end
	return { id = profile.id, name = type(profile.name) == "string" and profile.name or profile.id, util = util }
end

function P.FormatValue(v)
	return string.format("%g", v)
end

return P
