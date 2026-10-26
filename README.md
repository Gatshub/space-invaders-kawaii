# Space Invaders kawaii ♡

Petit Space Invaders dans le terminal — **Ruby + Charm Ruby** (gems `bubbletea` et `lipgloss`, ports des librairies Go de Charm).

## Jouer

    space-invaders        # si installé dans ~/.local/bin
    # ou
    ruby invaders.rb

## Règles

- Défends la galaxie : détruis les 18 (ou 28/32) envahisseurs avant qu'ils n'atteignent le sol.
- Une seule balle ♡ à l'écran — le tir compte, visez bien (les envahisseurs esquivent !).
- Attention aux bombes * : chaque touche coûte une vie ♡.

## Niveaux

| Niveau    | Formation | Cadence | Bombes | Vies |
|-----------|-----------|---------|--------|------|
| facile    | 3×6       | lente   | rares  | 4    |
| moyen     | 4×7       | moyenne | normales | 3  |
| difficile | 4×8       | rapide  | fréquentes | 2 |

## Touches

`←→` bouger · `espace` tirer · `n` rejouer · `m` menu · `q` quitter

## Couleurs

Palette adaptative (`Lipgloss::AdaptiveColor`) : suit le thème clair ou sombre du terminal. Kawaii assuré : kaomoji, ♡, 🐾.

## Tests

    ruby test/unit_logic.rb    # victoire, défaites, score, clamps

## Build

Dépendances : Ruby 3.2+, puis `bundle install`.
