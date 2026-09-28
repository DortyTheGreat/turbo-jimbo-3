# Turbo JIMBO 3

> Are you bad at poker? Now you can be bad even faster!

A client-side **Don't Starve Together** mod for the JIMBO minigame. It adds quality-of-life features and a **Smart AI** that plays or hints the best joker and discards. The AI calculates with the game's real server-side scoring rules, not the wiki's approximations.

[Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3809582066) · Based on [Turbo JIMBO 2](https://steamcommunity.com/sharedfiles/filedetails/?id=3467352009)

---

## Features

**Quality of life**
- **Turbo**: removes the animation delays.
- **Replay**: starts the next game automatically when you are idle.
- **Autoplay**: plays whole games for you.
- **Reveal cards**: shows your starting hand before you pick a joker.
- **Skip ending**: closes the screen right after the final deal. You still get the reward.

**Smart AI**
- **Joker choice**: rates each of the three offered jokers against your actual starting hand.
- **Discards**: picks the best cards to discard in both deals.
- **Hints**: shows the AI's advice under the buttons when you play manually. **BEST JOKER** and **BEST MOVE** apply it with one click.
- **Auto reroll**: optionally closes weak starts *before* a joker is picked, which costs nothing.
- **ODDS panel**: shows the chance of every reward, from monsters to gems.

## Results

These are simulated full games. Scores were computed by the game's own server code.

|                                   | Monsters (<120) | Bananas or better (200+) | Gold (600+) | Loot value / game* |
|-----------------------------------|:---------------:|:------------------------:|:-----------:|:------------------:|
| Old autoplay macros (v0.4)        | 21.2%           | 51%                      | 3.3%        | −0.53              |
| Smart AI                          | **4.0%**        | **73%**                  | 3.2%        | **0.71**           |
| Smart AI + auto reroll (0.5)      | **~1%**         | **~82%**                 | ~3.7%       | **1.04**           |

\* Loot value is a rough gold equivalent: monsters count as −6, and the top tier as +22.

The AI mostly removes losses. It does not create jackpots: 1400+ happens in only about 0.1% of games. The math only allows it with Wurt plus four or five face cards, and no strategy can change that.

## Rewards

| Score | Reward                                   |
|------:|------------------------------------------|
| < 120 | Monsters (killer bees, hounds or spiders) |
|   120 | Grass + twigs                            |
|   150 | Cut stone + rope                         |
|   200 | Bananas + playing cards                  |
|   400 | Banana pops + playing cards              |
|   600 | 2 gold + playing cards + record          |
|  1000 | 8 gold + playing cards + record          |
|  1400 | 12 gold + 3 gems + playing cards + record |

## Settings

Everything is in the in-game **CONFIGS** panel and saved automatically.

| Option                | What it does |
|-----------------------|--------------|
| Turbo                 | Removes animation delays. |
| Replay                | Restarts the machine after a game ends. It waits if you are busy. |
| Autoplay              | Plays the whole game automatically. |
| Skip ending           | Closes the screen after the final deal. |
| Reveal cards          | Flips your starting hand before the joker pick. |
| Macros end round      | Macro buttons also press **Deal**. |
| Smart AI              | Uses the solver. When off, the mod uses the classic hand-written macros and your joker ranking. |
| Auto reroll           | Rerolls weak starts. Needs Autoplay and Replay. |
| Goal                  | **Balanced** (best overall loot), **Jackpot** (chase 1400+) or **Safe** (avoid monsters above all). |
| Thinking              | Fast / Normal / Deep / Very deep. Sets how many simulations run per decision. |
| Auto reroll if loot < | Threshold for rerolling a start. **0.5** gives the most loot per minute. |

While Smart AI is on, its settings replace the joker ranking in the panel. Turn Smart AI off to edit the ranking.

## ODDS panel

The panel is a table of chances for all 8 rewards, plus the expected loot value.

| Column         | Meaning |
|----------------|---------|
| Joker names    | On the joker screen: the odds with each offered joker. `*` marks the AI's pick. |
| **AI**         | The odds if you follow the AI's plan for this game. |
| **Marked**     | Final deal only: the exact odds for the cards you have currently marked. Updates on every click. |
| **Avg**        | Long-run odds per game with your current settings, including rerolls. |
| **Played**     | Your real results: games played and rerolls. |

The odds are honest. The AI picks its move on one set of simulations and measures the odds on a separate, independent set. In 900 simulated games, predicted odds matched actual outcomes within about 1.5 percentage points for every reward tier.

## How the AI works

- **Exact rules.** `scripts/turbojimbo_brain.lua` ports the server's scoring code (`balatro_score_utils.lua`), quirks included.
- **Expectimax search.** The final discard is evaluated for all 32 options: exactly for 0–2 discarded cards, by sampling for 3–5. The first discard uses nested Monte Carlo: it samples the replacement cards, then solves the final discard for each sample. Successive halving gives most of the budget to the promising moves.
- **Objective.** The AI maximizes the expected value of the reward tiers under the chosen Goal. It does not maximize the raw score.
- **Performance.** A whole game takes about 0.5 s of computation, spread over frames at about 12 ms per frame, so the game does not stutter.

### Rule quirks the wiki doesn't mention

- **Aces** are worth 11 chips but are **not** face cards (for Wurt and Willow).
- **Wurt, Winona and Wormwood** also trigger when you skip a deal. Wurt gives 10 × (face cards kept)² chips per deal.
- **Wendy, Webber and Wes** only trigger if at least one card is replaced.
- **WX-78**: a heart kept in deal 1 and discarded in deal 2 gives +2 mult.
- **Wilson** counts pairs with a position-dependent bug. Two pair in slots 1-2 and 3-4 counts as one pair; trips in slots 1, 2 and 4 count as two.
- **Discarded cards** never return to the deck.
- **Closing the game before picking a joker** gives no reward and no penalty, so it works as a free reroll. Closing after picking spawns monsters. The mod never auto-closes after a pick.

## Installation

- **Steam:** subscribe on the [Workshop page](https://steamcommunity.com/sharedfiles/filedetails/?id=3809582066), then enable the mod in **Mods**.
- **Manual:** copy the mod folder into `Don't Starve Together/mods/`.

This is a client-only mod. It works on any server and other players don't need it.

## Project structure

```
modinfo.lua                    mod metadata
modmain.lua                    UI, game tracking, autoplay, panels
scripts/turbojimbo_brain.lua   solver: pure Lua 5.1, no game dependencies, reusable
scripts/turbojimbo_stats.lua   long-run odds for the Avg column (generated from simulations)
scripts/strings.lua            all UI text
scripts/persistentdata.lua     saved settings and stats
```

## Credits

- **Crestwave**: original Turbo JIMBO.
- **Crestwave & stod**: Turbo JIMBO 2.
- **DortyTheGreat**: Turbo JIMBO 3 (Smart AI, ODDS panel). Idea provided by me, code made by **Claude Opus 5.5 Extra**
