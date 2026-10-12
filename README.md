# UNO

A Godot 4.7 project for a simple UNO game.

## Project layout

- `scenes/` — game and interface scenes
- `scripts/` — game rules, card logic, and interface scripts
- `assets/` — card and interface art, audio, and fonts
- `resources/` — reusable card data and UI themes

Keep assets grouped by purpose and use `res://` paths when referencing project files.

## Combat prototype

Run the project to open one playable encounter. Click a card matching the active color, number, or action symbol; a Wild card lets you choose a color. You can also draw one card and end your turn. The action log shows what happened after each round. Restart encounter begins another trial.

This prototype follows the provisional combat loop in the [team GDD](https://docs.google.com/document/d/1Ss3C3PTpBP75-82laqm-AqZfYf2Ssnltn_Cl1EipD-0/edit): valid player cards deal 1 damage, enemy UNO cards change the shared discard state, the enemy attacks every two completed rounds, and emptying a hand triggers a 3 damage All-Out Attack followed by a refill if combat continues. Replay allows another card action; Skip omits the opponent's next UNO action. A round counter advances once after the player sequence and enemy UNO action, even when an action is skipped.

The current 8 HP, 5-card hands, shared draw pile, card mix, 3 damage All-Out Attack, and attack timing are experimental values for playtesting. The GDD does not yet settle encounter balance or broader run progression. Menus, rewards, map, and art assets are outside this prototype.
