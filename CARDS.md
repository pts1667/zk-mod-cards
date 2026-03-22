# Cards

The following is a list of complete and incomplete cards:

## Complete

### Reinforced Frames

Applies 5% max HP bonus (Additive) per minute to each unit on the team.
Associated gadget: `LuaRules/Gadgets/card_team_hp_growth.lua`
Category: Good

### Meteor Shower

Meteors occasionally drop in an area around your buildings and units.
Meteors size, aoe and damage are random. Meteor impact leaves behind reclaimable metal (~200 - 500 metal depending on meteor size)
Category: Neutral

### Raider Squads

Raiders, when built, split into 5 miniature units with 25% max HP and 40% unit size each.
Raiders can't be reclaimed, and leave no reclaimable metal debris on death.
Category: Good

### Metal Fuel

When units move, they expend metal in proportion to their metal cost and move speed.
When travelling from one side of a small map to the other, it should generally take around ~30% of the unit cost.
If there is no metal to take, apply a 90% move speed slow effect (check every ~3s)
Mobile units cost 90% less metal.
Category: Neutral

### Irreplacable Parts

Unit repairs cost metal.
Category: Bad

### Storage Mania

Gain a 1% bonus to metal extractors for every 750 metal held in storage.
Category: Good

### Energy Overload

Singularity reactors begin to decay (lose HP) at a rate of 2.5% max HP per second.
The rate of decay increases, to around 25% max HP per second 20 minutes after the reactor has been built.
Singularity reactors produce 100% extra energy to 400% extra energy after 20 minutes.
Category: Neutral

### Tanks

Only the tank factory is able to produce units.
All other factories are destroyed if built.
Category: Bad

### Commanders

Commanders are buffed- they gain 50% move and attack speed, 30% attack range, 100% build speed and 100% Max HP.
Ensure this is applied correctly when units are upgraded.
Category: Good

### The Reclaimer

When a unit on your team kills a unit on an enemy team, you gain the destroyed units' metal value in full and the destroyed unit leaves behind no reclaimable debris.
Category: Good

### Energy Shortage

Team energy will begin to vary over time, from 20% efficiency to 120% efficiency.
Category: Bad

### Builders

Constructors produce metal at a rate of 0.4 metal/sec and consume energy at a rate of 1 energy/sec. Metal extractors no longer produce metal.
Factories can only build constructors. No other mobile units may be built.
Associated gadget: `LuaRules/Gadgets/card_builders.lua`
Category: Neutral

### Nuclear Wildcard

Trinity will be stockpiled for free and takes only 30 seconds to stockpile.
The target position when launched is completely random.
Associated gadget: `LuaRules/Gadgets/card_nuclear_wildcard.lua`
Category: Neutral

### Strider Party

Striders, when built, have 20% Max HP and 40% size, but can be built at 40% of the cost.
Associated gadget: `LuaRules/Gadgets/card_strider_party.lua`
Category: Neutral

### Bounties

Every 5 minutes whilst there is no active bounty on your team, a random built, high-value building or unit from your team is picked and all other players have permanent line of sight in a radius of it.
An announcement is made: if <player>'s <unit name> is destroyed, everyone gets an economy bonus.
If that unit is destroyed, all other teams gain a 30% economy boost for 5 minutes while you get a 50% economy pentalty for 3 minutes.
Associated gadget: `LuaRules/Gadgets/card_bounties.lua`
Category: Bad

### Salvage Rights

All wrecks on the map contain 50% more metal. If multiple teams pick this, apply additively.
Associated gadget: `LuaRules/Gadgets/card_salvage_rights.lua`
Category: Neutral

## Incomplete

### Rapid Deployment

Factories and factory plates build units 200% faster, but all newly finished mobile units start with a 20 second disarm.
Category: Neutral

### Frontier Economy

Metal extractors produce 25% more metal when no enemy units are nearby, but 25% less metal while contested.
Cloaked units aren't counted.
Category: Neutral

### Siege Doctrine

Static defenses gain 50% range and 25% slower turn rate; mobile combat units lose 25% move speed.
Category: Neutral

### Emergency Reserves

When metal or energy storage drops below a threshold, the team receives a short burst of extra income or storage efficiency.
Category: Good

### Hardened Logistics

Static units have 50% bonus max HP and repair twice as fast.
Category: Good

### Field Repairs

All idle mobile units slowly regenerate health after being out of combat (i.e. not attacked) for a short period.
Category: Good

### Deep Magazines

Units with burst weapons reload more slowly between bursts, but gain a larger burst size or magazine capacity.
Category: Good

### Fragile Munitions

Weapons gain a small chance to misfire, dealing reduced damage or briefly stunning the firing unit.
Category: Bad

### Corroded Armor

All non-commander units slowly lose a small percentage of max HP (5% per minute).
Category: Bad

### Inefficient Refining

Metal extractors produce more slowly unless they have at least 150% overdrive.
Category: Bad

### Battlefield Panic

When an allied unit dies, nearby allied units are briefly slowed or disarmed.
Category: Bad

### Knockback

Weapons apply knockback (impulse damage in the opposite direction) proportional to the damage that weapon applies.
Category: Bad

### Mega Lobster

Lobsters have 500% bonus HP, 100% bonus size and 100% bonus range. Additionally, they can throw buildings.
Category: Good

### Sleep

Your units grow tired and must sleep. Units must sleep for 30 seconds once every 5 minutes.
During sleep, they can't do anything (but regenerate at 2 max HP/second).
Should be implemented in a similar way to EMP/Slow/Disarm, with its own effect and status bar.
Category: Bad

### Pre-Charged Shields

Shields can't recharge; however, they gain 10x their charge capacity when built.
Category: Neutral

### Lead the Charge

If you have at least 5 of a mobile unit, one of those mobile units (selected at random) is assigned as a Leader.
Leaders gain +200% Max HP, +50% size, +100% attack range and +100% attack speed. 
Additionally, all units of the same type within attack range gain a smaller bonus (+40% attack range and speed, no max HP bonus).
If the Leader dies all units of that type on the same team in attack range also die. In this case, a new leader is selected when there are again at least 5 units of that type.
Leaders should have a color tint/glow which can be implemented similar to the EMP/Slow/Disarm effects.
Category: Good

### Be Careful

If all commanders on your team are dead, all units on your team also die.
Category: Bad

### Monopoly

If your team has the highest metal income, gain 50% bonus metal income.
Measured by average metal income over the last 3 minutes.
Category: Good

### Air Dominance

Air units move at only 20% move speed, but rearm in the air and have +500% Max HP
Category: Good