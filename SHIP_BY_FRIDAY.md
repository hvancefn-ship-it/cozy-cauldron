# Cozy Cauldron — Ship Plan (Friday Target)

## Goal
Ship a polished vertical slice build by Friday with:
- Stable core gameplay loop
- Cohesive art/audio theme
- Beginner-friendly onboarding
- Exported playable build + itch page assets

## Scope Lock (must-have)
1. Brew loop (draw symbols → create potion)
2. Sell loop (customers + gold)
3. Upgrades (core rows only, balanced)
4. Gnomes automation
5. Prestige reset flow
6. Save/load reliability

## This Week Execution

### Day 1 — Stability + Architecture
- [x] Remove private cross-scene calls in prestige flow
- [x] Add public reset APIs (`UpgradeManager.reset_for_prestige`, `Shop.reset_for_prestige`)
- [x] Fix tab/scroll visibility edge case
- [x] Add save hardening + migration-safe loading (`upgrades`, `prestige`)
- [ ] Run regression pass (brew/sell/upgrade/prestige)

### Day 2 — Art Style Pass
- [ ] Choose one cohesive asset pack style (cozy fantasy UI + icons + FX)
- [ ] Replace placeholder rectangles with themed sprites
- [ ] Add consistent typography + palette
- [ ] Add background/environment layers

### Day 3 — Juice + Audio
- [ ] SFX pass: draw success/fail, bottle complete, coin gain, button click
- [ ] Music loop + volume controls
- [~] Tween/particles for key moments (brew complete, sale, prestige) *(started: cauldron hit pulse + gold/feedback pop)*

### Day 4 — UX + Tutorial
- [x] First-run tutorial (3-step guided flow)
- [ ] Better affordance labels on upgrades and tabs
- [ ] Tooltips or short descriptions on mechanics
- [ ] Performance pass for mobile profile

### Day 5 — Build + Itch Delivery
- [ ] Export Windows build
- [ ] Create itch page assets (capsule, screenshots, GIF)
- [ ] Write short store description + controls + known issues
- [ ] Smoke test final build and package release notes

## Asset Sources (safe, practical)
- Godot Asset Library (plugins/tools)
- Kenney (CC0 packs)
- itch.io game assets (filter for free/commercial-use license)
- OpenGameArt (verify individual licenses)

## Ship Criteria
- No crashes in a 20-minute session
- Save/load survives restart
- Prestige can be completed and rebought without data corruption
- At least one full run feels readable and rewarding
- Visual/audio style feels cohesive (not placeholder)
