# Zero-K Cards

`Zero-K Cards` is a gameplay mutator mod for [Zero-K](https://zero-k.info/), the 3D real-time strategy game built on the Recoil/Spring engine lineage.

The core idea is that teams periodically receive a card draft during the match. Each draft offers a small set of randomly selected cards, and the team votes on which one to take. Picked cards apply permanent match-long mutators or effects to the team that chose them, and some cards may eventually affect the wider battlefield as well.

## What The Mod Is

This mod is intended to add high-impact, team-level gameplay variation to standard Zero-K matches through cards.

Cards are designed to:

- apply persistent team mutators
- create significant strategic swings
- force adaptation over the course of a match
- support positive, negative, and neutral outcomes

In other words, this is not a cosmetic overlay or a minor rules tweak. The goal is a card system that materially changes how a match unfolds.

## Current Direction

The mod currently includes:

- the core synced card-draft and voting system
- Chili UI for drafting and vote selection
- a picked-cards HUD panel
- the first real gameplay-effect card pipeline

The design supports:

- team-wide card drafts
- permanent picked-card history
- unique card gadgets for cards with bespoke gameplay behavior

## Card Categories

The planned card pools are:

- `Neutral`: cards with broadly even or sideways effects
- `Good`: cards that benefit the team that picks them
- `Bad`: cards that impose a drawback on the team that picks them

Each draft stage uses a single category globally, so all teams draft from the same category for that stage.

## AI Disclaimer

Code primarily made using GPT Codex (model: GPT-5.4).
No AI-generated images or artwork have been used.