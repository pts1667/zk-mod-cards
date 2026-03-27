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

Gain a 1% bonus to metal extractors for every 250 metal held in storage.
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

### Rapid Deployment

Factories and factory plates build units 200% faster, but all newly finished mobile units start with a 20 second disarm.
Associated gadget: `LuaRules/Gadgets/card_rapid_deployment.lua`
Category: Neutral

### Frontier Economy

Metal extractors produce 25% more metal when no enemy units are nearby, but 25% less metal while contested.
Cloaked units aren't counted.
Associated gadget: `LuaRules/Gadgets/card_frontier_economy.lua`
Category: Neutral

### Siege Doctrine

Static defenses gain 50% range and 25% slower turn rate; mobile combat units lose 25% move speed.
Associated gadget: `LuaRules/Gadgets/card_siege_doctrine.lua`
Category: Neutral

### Emergency Reserves

When metal or energy storage drops below a threshold, the team receives a short burst of extra income or storage efficiency.
Associated gadget: `LuaRules/Gadgets/card_emergency_reserves.lua`
Category: Good

### Hardened Logistics

Static units have 50% bonus max HP and repair twice as fast.
Associated gadget: `LuaRules/Gadgets/card_hardened_logistics.lua`
Category: Good

### Field Repairs

All idle mobile units slowly regenerate health after being out of combat (i.e. not attacked) for a short period.
Associated gadget: `LuaRules/Gadgets/card_field_repairs.lua`
Category: Good

### Deep Magazines

Units with burst weapons reload more slowly between bursts, but gain a larger burst size or magazine capacity.
Associated gadget: `LuaRules/Gadgets/card_deep_magazines.lua`
Category: Good

### Lead the Charge

If you have at least 5 of a mobile unit, one of those mobile units (selected at random) is assigned as a Leader.
Leaders gain +200% Max HP, +50% size, +100% attack range and +100% attack speed. 
Additionally, all units of the same type within attack range gain a smaller bonus (+40% attack range and speed, no max HP bonus).
If the Leader dies all units of that type on the same team in attack range also die. In this case, a new leader is selected when both 3 minutes have passed and there are again at least 5 units of that type.
Leaders should have a color tint/glow which can be implemented similar to the EMP/Slow/Disarm effects.
Associated gadget: `LuaRules/Gadgets/card_lead_the_charge.lua`
Category: Good

### Fragile Munitions

Weapons gain a small chance to misfire, dealing reduced damage or briefly stunning the firing unit.
Associated gadget: `LuaRules/Gadgets/card_fragile_munitions.lua`
Category: Bad

### Corroded Armor

All non-commander units slowly lose a small percentage of max HP (5% per minute).
Associated gadget: `LuaRules/Gadgets/card_corroded_armor.lua`
Category: Bad

### Inefficient Refining

Metal extractors produce more slowly unless they have at least 150% overdrive.
Associated gadget: `LuaRules/Gadgets/card_inefficient_refining.lua`
Category: Bad

### Battlefield Panic

When an allied unit dies, nearby allied units are briefly slowed or disarmed.
Associated gadget: `LuaRules/Gadgets/card_battlefield_panic.lua`
Category: Bad

### Knockback

Weapons apply knockback (impulse damage in the opposite direction) to the firing unit proportional to the damage that weapon applies.
Associated gadget: `LuaRules/Gadgets/card_knockback.lua`
Category: Bad

### Sleep

Your units grow tired and must sleep. Units must sleep for 30 seconds once every 5 minutes.
During sleep, they can't do anything (but regenerate at 2 max HP/second).
Should be implemented in a similar way to EMP/Slow/Disarm, with its own effect and status bar.
Associated gadget: `LuaRules/Gadgets/card_sleep.lua`
Associated widget: `LuaUI/Widgets/gui_sleep_status.lua`
Category: Bad

### Mega Lobster

Lobsters have 500% bonus HP, 100% bonus size and 100% bonus range. Additionally, they can throw buildings.
Associated gadget: `LuaRules/Gadgets/card_mega_lobster.lua`
Category: Good

### Pre-Charged Shields

Shields can't recharge; however, they gain 10x their charge capacity when built.
Associated gadget: `LuaRules/Gadgets/card_pre_charged_shields.lua`
Category: Neutral

### Be Careful

If all commanders on your team are dead, all units on your team also die.
Associated gadget: `LuaRules/Gadgets/card_be_careful.lua`
Category: Bad

### Monopoly

If your team has the highest metal income, gain 50% bonus metal income.
Measured by average metal income over the last 3 minutes.
Associated gadget: `LuaRules/Gadgets/card_monopoly.lua`
Category: Good

### Air Dominance

Air units move at only 20% move speed, but rearm in the air and have +200% Max HP
Associated gadget: `LuaRules/Gadgets/card_air_dominance.lua`
Category: Good

### No Terraform

You can no longer terraform.
Associated gadget: `LuaRules/Gadgets/card_no_terraform.lua`
Category: Bad

### Lobster Airlines

Hercules and Charon gain 1500% bonus HP, but ground units can no longer move without the assistance of air transport.
Associated gadget: `LuaRules/Gadgets/card_lobster_airlines.lua`
Category: Neutral

### Economy Pack

You no longer gain metal from metal extractors; instead, your commanders' economy packs grow with commander level, beginning at base +4/4 metal/energy a second at level 1 (the default).
Caps at +20/+20 metal/energy a second at level 20.
Associated gadget: `LuaRules/Gadgets/card_economy_pack.lua`
Category: Good

### Heavy Tanks

Tanks get an 80% movespeed penalty, but gain 200% bonus Max HP, 100% bonus unit size, and burst-fire in shots of 3 (see `unit_tech_k.lua`).
Associated gadget: `LuaRules/Gadgets/card_heavy_tanks.lua`
Category: Neutral

### Booster Jets

Assault and riot units (including Dante) get booster jets. These push the unit forward and halve damage until the booster jet effects end.
Activates automatically when target unit is out of range, or when target position is out of range and enemy units are nearby (i.e within 1.5x attack range). Checked periodically.
Lasts for 4 seconds and has a cooldown of 30 seconds.
Associated gadget: `LuaRules/Gadgets/card_booster_jets.lua`
Category: Good

### Point Defense

All weapons now reload (almost) instantly. Instead of reloading, weapon range now grows gradually over time (from 1% range mult to 100% range mult), approaching 100% range mult at reload time.
Weapons that stockpile aren't affected.
Doesn't apply for units with multiple weapons such as Paladin and Dante.
Associated gadget: `LuaRules/Gadgets/card_point_defense.lua`
Category: Neutral

## Incomplete
