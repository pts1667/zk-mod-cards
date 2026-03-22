# Cards

The following is a list of complete and incomplete cards:

## Complete

### Reinforced Frames

Applies 5% max HP bonus (Additive) per minute to each unit on the team.
Associated gadget: `LuaRules/Gadgets/card_team_hp_growth.lua`
Category: Good

## Incomplete

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
Category: Neutral

### Nuclear Wildcard

Trinity will be stockpiled for free and takes only 30 seconds to stockpile.
The target position when launched is completely random.
Category: Neutral

### Strider Party

Striders, when built, have 20% Max HP and 40% size, but can be built at 40% of the cost.
Category: Neutral

### Bounties

Every 10 minutes, a random built, high-value building or unit is picked and all other players have permanent line of sight in a radius of it.
An announcement is made: if <player>'s <unit name> is destroyed, everyone gets an economy bonus.
If that unit is destroyed, all other teams gain a 30% economy boost for 5 minutes while you get a 50% economy pentalty for 5 minutes.
Category: Bad

### Salvage Rights

All wrecks on the map contain 50% more metal. If multiple teams pick this, apply additively.
Category: Neutral

### Rapid Deployment

Factories build units 100% faster, but all newly finished mobile units start with a 20 second disarm.
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

Constructors and factories take 20% less damage, and nanospray repair rate is increased.
Category: Good

### Adaptive Plating

Each unit gains a small permanent damage resistance bonus after surviving for several minutes, capped at a reasonable limit.
Category: Good

### Field Repairs

Idle mobile units slowly regenerate health after being out of combat for a short period.
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