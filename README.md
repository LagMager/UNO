# UNO

A Godot 4.7 project for a simple UNO game.

## Project layout

- `scenes/` — game and interface scenes
- `scripts/` — game rules, card logic, and interface scripts
- `assets/` — card and interface art, audio, and fonts
- `resources/` — reusable card data and UI themes

Keep assets grouped by purpose and use `res://` paths when referencing project files.

## Combat prototype

Run the project to open a selection panel. Choose Standard (the original enemy), Aggressor (attacks every round), or Trickster (prefers Replay and Skip), or play all three in that order. In the three-encounter test, remaining player HP carries forward and 3 HP is restored between wins, up to the 8 HP maximum. A win offers the next encounter; a defeat ends the run. Restart run returns to its first fight, and Choose mode returns to the selection panel.

In combat, click a card matching the active color, number, or action symbol; a Wild card lets you choose a color. You can also draw one card and end your turn. The action log shows what happened after each round. The enemy panel shows its attack timing and UNO card preference for behavior testing.

The player now owns a 60-card starter collection. Use **Deck** in combat to inspect its composition. Each encounter copies that collection into the shared draw pile, so both participants still draw from the same pile and cards played during combat do not remove cards from the collection. Collection changes made through `player_deck.gd` take effect in the next encounter of a three-fight run. Starting or restarting a run, or starting a single-enemy test, restores the starter collection. Card rewards and an in-game deck editor are not part of this prototype yet.

This prototype follows the provisional combat loop in the [team GDD](https://docs.google.com/document/d/1Ss3C3PTpBP75-82laqm-AqZfYf2Ssnltn_Cl1EipD-0/edit): valid player cards deal 1 damage, enemy UNO cards change the shared discard state, Standard and Trickster attack every two completed rounds while Aggressor attacks every round, and emptying a hand triggers a 3 damage All-Out Attack followed by a refill if combat continues. Replay allows another card action; Skip omits the opponent's next UNO action. A round counter advances once after the player sequence and enemy UNO action, even when an action is skipped.

Round resolution order: the player plays a card or draws; card damage and Replay/Skip effects resolve; an empty hand triggers All-Out Attack and refill; the enemy then takes its UNO action unless Skip prevents it; the round counter advances; and the scheduled attack fires when that enemy's configured interval is reached. Enemy Skip omits the next player UNO action, so the enemy sequence for that following round resolves before control returns to the player. Victory or defeat stops the sequence immediately. The encounter rejects further player actions until control returns to the player.

The card mix, labels, damage, Replay/Skip parameters, and card validation live in `scripts/game/card_catalog.gd`. `player_deck.gd` owns the persistent player card collection and produces independent combat copies. Encounter-level balance values remain in `scripts/game/encounter.gd`. `Encounter` owns card legality, combat piles, round order, damage resolution, outcomes, and event history. `enemy_ai.gd` selects a playable card or Wild color using the legality rule supplied by `Encounter`; it does not resolve actions. `enemy_profiles.gd` holds shared configuration, while `enemy_state.gd` holds the current enemy's ID, hand, and health. `Encounter` retains its existing public enemy properties as accessors. Player health and hand remain in `Encounter` until distinct player classes need their own runtime data.

Run deterministic checks with `godot --headless --path . --script res://tests/encounter_test.gd` and `godot --headless --path . --script res://tests/ui_test.gd`.

The current 8 HP, 5-card hands, shared draw pile, card mix, 3 damage All-Out Attack, enemy profiles, and between-fight recovery are experimental values for playtesting. The GDD does not yet settle encounter balance or broader run progression. Rewards, map, and art assets are outside this prototype.
