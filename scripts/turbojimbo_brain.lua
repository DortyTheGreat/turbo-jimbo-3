--[[
Turbo JIMBO brain.

Pure Lua 5.1 (no game dependencies), so it can be unit tested outside of DST.

The rules are a faithful port of the SERVER scoring code
(scripts/prefabs/balatro_score_utils.lua). The server decides the reward,
the client widget only shows animations, so we mirror the server, including
its quirks:
  * Ace counts 11 chips, J 11, Q 12, K 13. Ace is NOT a face card (Wurt/Willow).
  * Joker effects that trigger "on discard" also trigger when you SKIP
    (Wurt, Winona, Wormwood score on every deal, even without discarding).
  * Wendy / Webber / Wes only trigger when at least one card is replaced.
  * WX-78: a heart kept in deal 1 and discarded in deal 2 gives +2 mult.
  * Wilson counts pairs with a buggy, position dependent algorithm
    (two pair in slots 1-2/3-4 counts as ONE pair, trips in slots 1,2,4
    count as TWO). We replicate it exactly.
  * Discarded cards never come back, replacements are drawn uniformly
    from the 52 card deck minus every card seen so far.

Strategy: expectimax over the two discard decisions.
  * Final discard: every one of the 32 discard masks is evaluated,
    exactly for 0-2 discards, with common-random-number sampling for 3-5.
  * First discard: nested Monte Carlo (sample the replacement cards, then
    solve the final discard for each sample) with successive halving so
    that most of the budget goes to the promising masks.
  * Joker choice: the same nested search for each offered joker.
The objective is the expected value of a configurable utility per reward tier,
so the AI plays for the jackpot (1400+) while avoiding the monster tier (<120).
]]

local Brain = {}

local floor, random, max = math.floor, math.random, math.max
local co_yield = coroutine.yield

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local SPADES, HEARTS, CLUBS, DIAMONDS = 1, 2, 3, 4

Brain.SCORE_RANKS = { 0, 120, 150, 200, 400, 600, 1000, 1400 }

Brain.JOKER_NAMES = {
	"walter", "wanda", "warly", "wathgrithr", "waxwell", "webber", "wendy", "wes",
	"wickerbottom", "willow", "wilson", "winona", "wolfgang", "woodie", "wormwood",
	"wortox", "wurt", "wx78",
}
local JCODE = {}
for i, name in ipairs(Brain.JOKER_NAMES) do JCODE[name] = i end
Brain.JCODE = JCODE

local WALTER, WANDA, WARLY, WATHGRITHR, WAXWELL, WEBBER, WENDY, WES,
	WICKERBOTTOM, WILLOW, WILSON, WINONA, WOLFGANG, WOODIE, WORMWOOD,
	WORTOX, WURT, WX78 = 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18

-- Utility of each reward rank (index = rank 1..8, see SCORE_RANKS).
-- Rank 1 spawns monsters, 6+ give gold, 8 gives 12 gold + 3 gems.
Brain.PROFILES = {
	balanced = { -6, 0.1, 0.5, 1, 1.5, 3, 9, 22 },
	jackpot  = { -2, 0, 0, 0.05, 0.1, 0.4, 2, 30 },
	safe     = { -25, 0.3, 0.6, 1.2, 2, 4, 9, 18 },
}

--------------------------------------------------------------------------------
-- Cards: internal ids 1..52, id = (suit-1)*13 + num. Game uses suit*100+num.
--------------------------------------------------------------------------------

local SUIT, NUM, VAL, NBIT, FACE, RED = {}, {}, {}, {}, {}, {}
for s = 1, 4 do
	for n = 1, 13 do
		local id = (s - 1) * 13 + n
		SUIT[id] = s
		NUM[id] = n
		VAL[id] = (n == 1) and 11 or n
		NBIT[id] = 2 ^ (n - 1)
		FACE[id] = n > 10
		RED[id] = (s == HEARTS or s == DIAMONDS)
	end
end

function Brain.FromGame(c)
	local s = floor(c / 100)
	return (s - 1) * 13 + (c - s * 100)
end

function Brain.ToGame(id)
	return SUIT[id] * 100 + NUM[id]
end

local RANK_CHARS = { "A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K" }
local SUIT_CHARS = { "S", "H", "C", "D" }
function Brain.CardName(id)
	return RANK_CHARS[NUM[id]] .. SUIT_CHARS[SUIT[id]]
end

-- Straights, keyed by the bitmask of the five (distinct) numbers. 2 = royal.
local STRAIGHT = {}
for lo = 1, 9 do
	local bits = 0
	for n = lo, lo + 4 do bits = bits + 2 ^ (n - 1) end
	STRAIGHT[bits] = 1
end
STRAIGHT[2 ^ 0 + 2 ^ 9 + 2 ^ 10 + 2 ^ 11 + 2 ^ 12] = 2 -- 10 J Q K A

-- Number of equal-number card pairs -> hand score (0 is handled separately).
local EQSCORE = { [1] = 2, [2] = 3, [3] = 4, [4] = 7, [6] = 8 }

--------------------------------------------------------------------------------
-- Discard masks 0..31 (bit i-1 set = slot i discarded)
--------------------------------------------------------------------------------

local MB, MK, MIDX = {}, {}, {}
for m = 0, 31 do
	local b, k, idx, x = {}, 0, {}, m
	for i = 1, 5 do
		local bit = x % 2
		x = (x - bit) / 2
		b[i] = bit == 1
		if b[i] then
			k = k + 1
			idx[k] = i
		end
	end
	MB[m], MK[m], MIDX[m] = b, k, idx
end
Brain.MASK_BITS = MB
Brain.MASK_COUNT = MK

function Brain.MaskFromBools(t)
	local m = 0
	for i = 1, 5 do
		if t[i] then m = m + 2 ^ (i - 1) end
	end
	return m
end

--------------------------------------------------------------------------------
-- Hand evaluation (mirror of BaseJoker:EvaluateHand)
--------------------------------------------------------------------------------

local function handscore(a, b, c, d, e)
	local na, nb, nc, nd, ne = NUM[a], NUM[b], NUM[c], NUM[d], NUM[e]
	local eq = 0
	if na == nb then eq = eq + 1 end
	if na == nc then eq = eq + 1 end
	if na == nd then eq = eq + 1 end
	if na == ne then eq = eq + 1 end
	if nb == nc then eq = eq + 1 end
	if nb == nd then eq = eq + 1 end
	if nb == ne then eq = eq + 1 end
	if nc == nd then eq = eq + 1 end
	if nc == ne then eq = eq + 1 end
	if nd == ne then eq = eq + 1 end
	if eq > 0 then
		return EQSCORE[eq]
	end
	local s = SUIT[a]
	local st = STRAIGHT[NBIT[a] + NBIT[b] + NBIT[c] + NBIT[d] + NBIT[e]]
	if SUIT[b] == s and SUIT[c] == s and SUIT[d] == s and SUIT[e] == s then
		if st == 2 then return 10 elseif st then return 9 end
		return 6
	end
	if st then return 5 end
	return 1
end
Brain.HandScore = handscore

-- Wilson: exact replica of the server loop, including the table.remove(t, index)
-- bug (removes by POSITION = card index; out of range removals are no-ops).
-- The result only depends on which slots hold equal numbers, so it is cached.
local wilson_cache = {}
local function wilson_pairs(a, b, c, d, e)
	local n = { NUM[a], NUM[b], NUM[c], NUM[d], NUM[e] }
	local key, w = 0, 1
	for i = 1, 4 do
		for j = i + 1, 5 do
			if n[i] == n[j] then key = key + w end
			w = w * 2
		end
	end
	local cached = wilson_cache[key]
	if cached then return cached end

	local numpairs = 0
	local idx = { 1, 2, 3, 4, 5 }
	while #idx >= 2 do
		local current = table.remove(idx, 1)
		local cnum = n[current]
		for _, index in ipairs(idx) do
			if n[index] == cnum then
				numpairs = numpairs + 1
				if index >= 1 and index <= #idx then
					table.remove(idx, index)
				end
				break
			end
		end
	end
	wilson_cache[key] = numpairs
	return numpairs
end
Brain.WilsonPairs = wilson_pairs

--------------------------------------------------------------------------------
-- Joker hooks (server semantics). State = chips, mult, last (wx78 mask or -1).
--------------------------------------------------------------------------------

-- OnCardsDiscarded: called for every deal, also for skips (m == 0).
-- h = array of the 5 current card ids. Returns chips, mult, last, wesprev.
local function on_discard(j, h, m, chips, mult, last)
	local b = MB[m]
	local wesprev
	if j == WALTER then
		local s1, s2, s3, s4 = 0, 0, 0, 0
		for i = 1, 5 do
			if b[i] then
				local s = SUIT[h[i]]
				if s == 1 then s1 = 1 elseif s == 2 then s2 = 1 elseif s == 3 then s3 = 1 else s4 = 1 end
			end
		end
		local u = s1 + s2 + s3 + s4
		if u > 0 then chips = chips + 15 * u end
	elseif j == WANDA then
		chips = max(0, chips - 15 * MK[m])
	elseif j == WAXWELL then
		for i = 1, 5 do
			if b[i] and SUIT[h[i]] == HEARTS then mult = mult + 1 end
		end
	elseif j == WES then
		wesprev = handscore(h[1], h[2], h[3], h[4], h[5])
	elseif j == WILLOW then
		for i = 1, 5 do
			if b[i] and FACE[h[i]] then chips = chips + 20 end
		end
	elseif j == WINONA then
		for i = 1, 5 do
			if not b[i] and SUIT[h[i]] == HEARTS then mult = mult + 1 end
		end
	elseif j == WOODIE then
		chips = chips + 7 * MK[m]
	elseif j == WORMWOOD then
		for i = 1, 5 do
			if not b[i] and SUIT[h[i]] == CLUBS then chips = chips + 15 end
		end
	elseif j == WORTOX then
		for i = 1, 5 do
			if b[i] and SUIT[h[i]] == HEARTS then chips = chips + 15 end
		end
	elseif j == WURT then
		local f = 0
		for i = 1, 5 do
			if not b[i] and FACE[h[i]] then f = f + 1 end
		end
		chips = chips + 10 * f * f
	elseif j == WX78 then
		if last >= 0 then
			local lb = MB[last]
			for i = 1, 5 do
				if not lb[i] and b[i] and SUIT[h[i]] == HEARTS then mult = mult + 2 end
			end
		end
		last = m
	end
	return chips, mult, last, wesprev
end

-- OnNewCards: only when at least one card was replaced.
local function on_newcards(j, o1, o2, o3, o4, o5, x1, x2, x3, x4, x5, m, chips, mult, wesprev)
	if j == WEBBER then
		local b = MB[m]
		if b[1] and RED[o1] and not RED[x1] then mult = mult + 2 end
		if b[2] and RED[o2] and not RED[x2] then mult = mult + 2 end
		if b[3] and RED[o3] and not RED[x3] then mult = mult + 2 end
		if b[4] and RED[o4] and not RED[x4] then mult = mult + 2 end
		if b[5] and RED[o5] and not RED[x5] then mult = mult + 2 end
	elseif j == WENDY then
		local b = MB[m]
		if b[1] and SUIT[o1] == SUIT[x1] then chips = chips + 5; mult = mult + 2 end
		if b[2] and SUIT[o2] == SUIT[x2] then chips = chips + 5; mult = mult + 2 end
		if b[3] and SUIT[o3] == SUIT[x3] then chips = chips + 5; mult = mult + 2 end
		if b[4] and SUIT[o4] == SUIT[x4] then chips = chips + 5; mult = mult + 2 end
		if b[5] and SUIT[o5] == SUIT[x5] then chips = chips + 5; mult = mult + 2 end
	elseif j == WES then
		if wesprev > handscore(x1, x2, x3, x4, x5) then chips = chips + 30 end
	end
	return chips, mult
end

-- GetFinalScoreRank: card chips, OnGameFinished, hand mult. Returns numeric score.
local function final_score(j, a, b, c, d, e, chips, mult)
	chips = chips + VAL[a] + VAL[b] + VAL[c] + VAL[d] + VAL[e]
	if j == WARLY then
		local sa, sb, sc, sd, se = SUIT[a], SUIT[b], SUIT[c], SUIT[d], SUIT[e]
		local h = (sa == 1 or sb == 1 or sc == 1 or sd == 1 or se == 1)
			and (sa == 2 or sb == 2 or sc == 2 or sd == 2 or se == 2)
			and (sa == 3 or sb == 3 or sc == 3 or sd == 3 or se == 3)
			and (sa == 4 or sb == 4 or sc == 4 or sd == 4 or se == 4)
		if h then mult = mult + 4 end
	elseif j == WATHGRITHR then
		if SUIT[a] == SPADES then chips = chips + 25 end
		if SUIT[b] == SPADES then chips = chips + 25 end
		if SUIT[c] == SPADES then chips = chips + 25 end
		if SUIT[d] == SPADES then chips = chips + 25 end
		if SUIT[e] == SPADES then chips = chips + 25 end
	elseif j == WICKERBOTTOM then
		if NUM[a] == 12 then mult = mult + 1 end
		if NUM[b] == 12 then mult = mult + 1 end
		if NUM[c] == 12 then mult = mult + 1 end
		if NUM[d] == 12 then mult = mult + 1 end
		if NUM[e] == 12 then mult = mult + 1 end
	elseif j == WILSON then
		mult = mult + 3 * wilson_pairs(a, b, c, d, e)
	elseif j == WOLFGANG then
		if NUM[a] == 13 then chips = chips + 25 end
		if NUM[b] == 13 then chips = chips + 25 end
		if NUM[c] == 13 then chips = chips + 25 end
		if NUM[d] == 13 then chips = chips + 25 end
		if NUM[e] == 13 then chips = chips + 25 end
	elseif j == WORTOX then
		local hts = 0
		if SUIT[a] == HEARTS then hts = hts + 1 end
		if SUIT[b] == HEARTS then hts = hts + 1 end
		if SUIT[c] == HEARTS then hts = hts + 1 end
		if SUIT[d] == HEARTS then hts = hts + 1 end
		if SUIT[e] == HEARTS then hts = hts + 1 end
		chips = max(0, chips - 11 * hts)
		mult = mult + hts
	end
	mult = mult + handscore(a, b, c, d, e)
	return chips * mult
end
Brain.FinalScore = final_score

function Brain.RankOf(score)
	if score >= 1400 then return 8
	elseif score >= 1000 then return 7
	elseif score >= 600 then return 6
	elseif score >= 400 then return 5
	elseif score >= 200 then return 4
	elseif score >= 150 then return 3
	elseif score >= 120 then return 2
	end
	return 1
end
local rank_of = Brain.RankOf

--------------------------------------------------------------------------------
-- Game tracker: replays the server logic from what the client observes.
--------------------------------------------------------------------------------

local Tracker = {}
Tracker.__index = Tracker

-- joker: name, hand: 5 game cards (suit*100+num)
function Brain.NewTracker(joker, gamehand)
	local t = setmetatable({}, Tracker)
	t.j = JCODE[joker]
	t.joker = joker
	t.hand = {}
	t.seen = {}
	for i = 1, 5 do
		local id = Brain.FromGame(gamehand[i])
		t.hand[i] = id
		t.seen[id] = true
	end
	t.chips, t.mult, t.last = 0, 0, -1
	if t.j == WANDA then t.chips = 80 end
	t.deal = 1 -- next deal index (1 or 2), 3 = finished
	return t
end

-- Apply one deal. m = discard mask, newgamehand = 5 game cards after the deal.
function Tracker:Record(m, newgamehand)
	local h = self.hand
	local chips, mult, last, wesprev = on_discard(self.j, h, m, self.chips, self.mult, self.last)
	if m ~= 0 then
		local x = {}
		for i = 1, 5 do
			x[i] = Brain.FromGame(newgamehand[i])
			self.seen[x[i]] = true
		end
		chips, mult = on_newcards(self.j, h[1], h[2], h[3], h[4], h[5], x[1], x[2], x[3], x[4], x[5], m, chips, mult, wesprev)
		self.hand = x
	end
	self.chips, self.mult, self.last = chips, mult, last
	self.deal = self.deal + 1
end

function Tracker:Deck()
	local d = {}
	for id = 1, 52 do
		if not self.seen[id] then d[#d + 1] = id end
	end
	return d
end

function Tracker:FinalScore()
	local h = self.hand
	return final_score(self.j, h[1], h[2], h[3], h[4], h[5], self.chips, self.mult)
end

--------------------------------------------------------------------------------
-- Search
--------------------------------------------------------------------------------

-- Cooperative multitasking: when run inside a coroutine with ctx.quota set,
-- yield after roughly `quota` leaf evaluations.
local function tick(ctx, n)
	local q = ctx.quota
	if q then
		local c = ctx.counter + n
		if c >= q then
			ctx.counter = 0
			co_yield()
		else
			ctx.counter = c
		end
	end
end

local function new_ctx(util, opts)
	opts = opts or {}
	return {
		util = util or Brain.PROFILES.balanced,
		quota = opts.quota,
		counter = 0,
		scale = opts.scale or 1, -- global budget multiplier
	}
end

-- Draw `len` distinct cards from deck into out[base+1..base+len] (partial Fisher-Yates).
local function sample_prefix(deck, n, len, out, base, work)
	for i = 1, n do work[i] = deck[i] end
	for t = 1, len do
		local r = random(t, n)
		local v = work[r]
		work[r] = work[t]
		work[t] = v
		out[base + t] = v
	end
end

-- For mask m: POS[m][slot] = index of the drawn card that lands in `slot` (0 = kept).
local POS = {}
for m = 0, 31 do
	local p, t = {}, 0
	for i = 1, 5 do
		if MB[m][i] then t = t + 1; p[i] = t else p[i] = 0 end
	end
	POS[m] = p
end

-- One leaf: kept cards a..e, drawn cards read from S[o+1..], returns reward rank.
local function leaf(j, a, b, c, d, e, p1, p2, p3, p4, p5, S, o, m, chips1, mult1, wesprev)
	local x1, x2, x3, x4, x5 = a, b, c, d, e
	if p1 > 0 then x1 = S[o + p1] end
	if p2 > 0 then x2 = S[o + p2] end
	if p3 > 0 then x3 = S[o + p3] end
	if p4 > 0 then x4 = S[o + p4] end
	if p5 > 0 then x5 = S[o + p5] end
	if j == WEBBER or j == WENDY or j == WES then
		chips1, mult1 = on_newcards(j, a, b, c, d, e, x1, x2, x3, x4, x5, m, chips1, mult1, wesprev)
	end
	return rank_of(final_score(j, x1, x2, x3, x4, x5, chips1, mult1))
end

-- Expected utility of ONE final-discard mask, given the hand h (before replacement)
-- and the state after the discard hooks. Exact for k <= exact_k, otherwise uses
-- the sample table S (stride 5, ns samples). Optionally fills rankcount[1..8].
local EXACT_BUF = { 0, 0, 0, 0, 0 }
local function eval_last_mask(ctx, j, h, m, chips1, mult1, wesprev, deck, n, S, ns, exact_k, rankcount)
	local U = ctx.util
	local k = MK[m]
	local a, b, c, d, e = h[1], h[2], h[3], h[4], h[5]
	if k == 0 then
		local r = rank_of(final_score(j, a, b, c, d, e, chips1, mult1))
		if rankcount then rankcount[r] = rankcount[r] + 1 end
		return U[r]
	end
	local pm = POS[m]
	local p1, p2, p3, p4, p5 = pm[1], pm[2], pm[3], pm[4], pm[5]
	local total, cnt = 0, 0
	if k <= exact_k then
		local B = EXACT_BUF
		if k == 1 then
			for p = 1, n do
				B[1] = deck[p]
				local r = leaf(j, a, b, c, d, e, p1, p2, p3, p4, p5, B, 0, m, chips1, mult1, wesprev)
				total = total + U[r]
				if rankcount then rankcount[r] = rankcount[r] + 1 end
			end
			cnt = n
		else -- k == 2
			for p = 1, n - 1 do
				B[1] = deck[p]
				for q = p + 1, n do
					B[2] = deck[q]
					local r = leaf(j, a, b, c, d, e, p1, p2, p3, p4, p5, B, 0, m, chips1, mult1, wesprev)
					total = total + U[r]
					if rankcount then rankcount[r] = rankcount[r] + 1 end
				end
			end
			cnt = n * (n - 1) / 2
		end
		tick(ctx, cnt)
	else
		for s = 0, ns - 1 do
			local r = leaf(j, a, b, c, d, e, p1, p2, p3, p4, p5, S, s * 5, m, chips1, mult1, wesprev)
			total = total + U[r]
			if rankcount then rankcount[r] = rankcount[r] + 1 end
		end
		cnt = ns
		tick(ctx, ns)
	end
	if rankcount then
		for r = 1, 8 do rankcount[r] = rankcount[r] / cnt end
	end
	return total / cnt
end

-- Solve the FINAL discard exactly/accurately. Returns best mask, table of values.
local function solve_last(ctx, j, h, deck, chips, mult, last, want_dist)
	local n = #deck
	local ns = floor(360 * ctx.scale)
	if ns < 60 then ns = 60 end
	local S, work = {}, {}
	for s = 0, ns - 1 do sample_prefix(deck, n, 5, S, s * 5, work) end

	local values, dists = {}, {}
	local best, bestv = 0, -1e9
	for m = 0, 31 do
		local c1, m1, _, wp = on_discard(j, h, m, chips, mult, last)
		local rc = want_dist and { 0, 0, 0, 0, 0, 0, 0, 0 } or nil
		local v = eval_last_mask(ctx, j, h, m, c1, m1, wp, deck, n, S, ns, 2, rc)
		values[m] = v
		dists[m] = rc
		if v > bestv + 1e-9 then best, bestv = m, v end
	end
	return best, values, dists
end

-- Fill S (stride 5) with the first 5 cards of each row of Q (stride 10) that are not
-- marked as used by the current sample.
local function fill_rows(Q, qbase, nq, used, stamp, S)
	for r = 0, nq - 1 do
		local o, t = qbase + r * 10, 0
		local so = r * 5
		for p = 1, 10 do
			local cid = Q[o + p]
			if used[cid] ~= stamp then
				t = t + 1
				S[so + t] = cid
				if t == 5 then break end
			end
		end
	end
end

-- Inner (approximate) final-discard solve used inside the first-discard search.
-- Returns the best value and the mask that achieves it.
local function inner_last_value(ctx, j, h, chips, mult, last, Q, qbase, nq, used, stamp, S)
	fill_rows(Q, qbase, nq, used, stamp, S)
	local bestv, bestm = -1e9, 0
	for m = 0, 31 do
		local c1, m1, _, wp = on_discard(j, h, m, chips, mult, last)
		local v = eval_last_mask(ctx, j, h, m, c1, m1, wp, nil, 0, S, nq, 0, nil)
		if v > bestv then bestv, bestm = v, m end
	end
	return bestv, bestm
end

-- Successive halving schedule for the first discard: {cumulative samples, survivors}
local FIRST_SCHEDULE = {
	{ 6, 10 },
	{ 18, 4 },
	{ 48, 2 },
	{ 80, 1 },
}

-- Apply a first-deal mask to hand h with drawn cards P[po+1..]; fills h2, marks used.
-- Returns chips, mult after the new-card hooks.
local function apply_first(j, h, h2, m, P, po, used, stamp, pr)
	local bm = MB[m]
	local t = 0
	for i = 1, 5 do
		if bm[i] then
			t = t + 1
			local cid = P[po + t]
			h2[i] = cid
			used[cid] = stamp
		else
			h2[i] = h[i]
		end
	end
	if MK[m] == 0 then
		return pr[1], pr[2]
	end
	return on_newcards(j, h[1], h[2], h[3], h[4], h[5], h2[1], h2[2], h2[3], h2[4], h2[5], m, pr[1], pr[2], pr[4])
end

-- Unbiased reward distribution of first mask m, followed by the (sampled) best final
-- discard. Uses FRESH samples: the final discard is chosen on one set of draws and
-- scored on an independent set, so the "winner's curse" does not inflate the odds.
local function fresh_distribution(ctx, j, h, deck, pr, m, neval, nq)
	local n = #deck
	local P, Q, R, work = {}, {}, {}, {}
	local acc = { 0, 0, 0, 0, 0, 0, 0, 0 }
	local rc = { 0, 0, 0, 0, 0, 0, 0, 0 }
	local used, stamp, S, h2 = {}, 0, {}, {}
	for s = 1, neval do
		sample_prefix(deck, n, 5, P, 0, work)
		for r = 0, nq - 1 do
			sample_prefix(deck, n, 10, Q, r * 10, work)
			sample_prefix(deck, n, 10, R, r * 10, work)
		end
		stamp = stamp + 1
		local ch, mu = apply_first(j, h, h2, m, P, 0, used, stamp, pr)
		local _, m2 = inner_last_value(ctx, j, h2, ch, mu, pr[3], Q, 0, nq, used, stamp, S)
		fill_rows(R, 0, nq, used, stamp, S)
		local c1, m1, _, wp = on_discard(j, h2, m2, ch, mu, pr[3])
		for r = 1, 8 do rc[r] = 0 end
		eval_last_mask(ctx, j, h2, m2, c1, m1, wp, nil, 0, S, nq, 0, rc)
		for r = 1, 8 do acc[r] = acc[r] + rc[r] end
	end
	for r = 1, 8 do acc[r] = acc[r] / neval end
	return acc
end

-- Solve the FIRST discard. Returns best mask, value estimates (per surviving mask),
-- and (if neval > 0) an unbiased reward distribution for the best mask.
local function solve_first(ctx, j, h, deck, chips, mult, last, schedule, nq, neval)
	schedule = schedule or FIRST_SCHEDULE
	nq = nq or 16
	local n = #deck
	local maxs = floor(schedule[#schedule][1] * ctx.scale + 0.5)
	if maxs < 4 then maxs = 4 end

	-- Outer draws P (5 per sample) and inner rows Q (nq rows x 10 per sample).
	local P, Q, work = {}, {}, {}
	for s = 0, maxs - 1 do
		sample_prefix(deck, n, 5, P, s * 5, work)
		for r = 0, nq - 1 do
			sample_prefix(deck, n, 10, Q, (s * nq + r) * 10, work)
		end
	end

	local used, stamp = {}, 0
	local S = {}
	local sum, cnt = {}, {}
	local alive = {}
	for m = 0, 31 do sum[m], cnt[m], alive[#alive + 1] = 0, 0, m end

	local h2 = {}
	-- precompute discard hooks for every first mask
	local pre = {}
	for m = 0, 31 do
		local c1, m1, l1, wp = on_discard(j, h, m, chips, mult, last)
		pre[m] = { c1, m1, l1, wp }
	end

	for stage = 1, #schedule do
		local upto = floor(schedule[stage][1] * ctx.scale + 0.5)
		if upto > maxs or stage == #schedule then upto = maxs end
		for _, m in ipairs(alive) do
			local pr = pre[m]
			for s = cnt[m], upto - 1 do
				stamp = stamp + 1
				local ch, mu = apply_first(j, h, h2, m, P, s * 5, used, stamp, pr)
				local v = inner_last_value(ctx, j, h2, ch, mu, pr[3], Q, s * nq * 10, nq, used, stamp, S)
				sum[m] = sum[m] + v
			end
			if upto > cnt[m] then cnt[m] = upto end
		end
		-- keep the best `survivors`
		local keep = schedule[stage][2]
		table.sort(alive, function(x, y)
			local vx, vy = sum[x] / cnt[x], sum[y] / cnt[y]
			if vx ~= vy then return vx > vy end
			return MK[x] < MK[y]
		end)
		local nxt = {}
		for i = 1, math.min(keep, #alive) do nxt[i] = alive[i] end
		alive = nxt
	end

	local values = {}
	for m = 0, 31 do
		if cnt[m] > 0 then values[m] = sum[m] / cnt[m] end
	end
	local best = alive[1]
	local dist
	if neval ~= nil and neval > 0 then
		dist = fresh_distribution(ctx, j, h, deck, pre[best], best, neval, nq)
	end
	return best, values, dist
end

local function neval_for(ctx, base)
	local n = floor(base * ctx.scale + 0.5)
	if n < 12 then n = 12 end
	return n
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

-- Expected value of a reward distribution under a utility table (default: balanced).
function Brain.ExpectedValue(dist, util)
	util = util or Brain.PROFILES.balanced
	local v = 0
	for r = 1, 8 do v = v + (dist[r] or 0) * util[r] end
	return v
end

-- Decide which cards to discard for the tracker's current deal.
-- Returns mask, info table:
--   value = search value (in `util` units), dist = reward distribution of the best mask,
--   dists = (final deal only) reward distribution of EVERY mask.
function Brain.DecideDiscard(tracker, util, opts)
	local ctx = new_ctx(util, opts)
	local deck = tracker:Deck()
	local h = tracker.hand
	if tracker.deal >= 2 then
		local best, values, dists = solve_last(ctx, tracker.j, h, deck, tracker.chips, tracker.mult, tracker.last, true)
		return best, { value = values[best], values = values, dist = dists[best], dists = dists }
	else
		local best, values, dist = solve_first(ctx, tracker.j, h, deck, tracker.chips, tracker.mult, tracker.last, nil, nil, neval_for(ctx, 40))
		return best, { value = values[best], values = values, dist = dist }
	end
end

-- Value of starting a game with `joker` and the given 5 game cards.
-- Returns search value, best first mask, reward distribution.
local JOKER_SCHEDULE = {
	{ 5, 6 },
	{ 14, 2 },
	{ 30, 1 },
}
function Brain.EvaluateJoker(joker, gamehand, util, opts)
	local ctx = new_ctx(util, opts)
	local t = Brain.NewTracker(joker, gamehand)
	local best, values, dist = solve_first(ctx, t.j, t.hand, t:Deck(), t.chips, t.mult, t.last, JOKER_SCHEDULE, 12, neval_for(ctx, 48))
	-- The search value is optimistic (max over noisy estimates) by a joker-dependent
	-- amount, so jokers are compared on the unbiased value of the fresh distribution.
	return Brain.ExpectedValue(dist, ctx.util), best, dist, values[best]
end

-- Choose among the offered jokers. Returns best index, values per index, distributions per index.
function Brain.ChooseJoker(jokers, gamehand, util, opts)
	local vals, dists, best, bestv = {}, {}, 1, -1e9
	for i, name in ipairs(jokers) do
		if JCODE[name] then
			local v, _, dist = Brain.EvaluateJoker(name, gamehand, util, opts)
			vals[i], dists[i] = v, dist
			if v > bestv then best, bestv = i, v end
		else
			vals[i] = -1e9
		end
	end
	return best, vals, dists
end

-- Coroutine job wrapper: job:Step() returns true when finished (result in job.result).
function Brain.NewJob(fn, quota)
	local job = { done = false }
	job.co = coroutine.create(function()
		job.result = { fn(quota) }
	end)
	function job:Step()
		if self.done then return true end
		local ok, err = coroutine.resume(self.co)
		if not ok then
			self.done = true
			self.error = err
			return true
		end
		if coroutine.status(self.co) == "dead" then
			self.done = true
		end
		return self.done
	end
	return job
end

-- internals exposed for tests
Brain._on_discard = on_discard
Brain._on_newcards = on_newcards

return Brain
