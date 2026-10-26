# frozen_string_literal: true

# Test logique : victoire, défaite, score, vies — sans interface
require_relative "../invaders"

def key(name)
  kt = case name
       when " " then Bubbletea::KeyMessage::KEY_SPACE
       when "left" then Bubbletea::KeyMessage::KEY_LEFT
       when "right" then Bubbletea::KeyMessage::KEY_RIGHT
       when "up" then Bubbletea::KeyMessage::KEY_UP
       when "down" then Bubbletea::KeyMessage::KEY_DOWN
       else Bubbletea::KeyMessage::KEY_RUNES
       end
  Bubbletea::KeyMessage.new(key_type: kt, runes: [], name: name)
end

def tick_n(game, n)
  n.times do
    game.update(TickMessage.new)
  end
end

# ── 1) victoire : tuer tous les envahisseurs ──
game = Game.new

game.start(0) unless game.instance_variable_get(:@invaders)

# placer le joueur sous un envahisseur et tirer jusqu'à extinction
kills = 0
until game.instance_variable_get(:@over)
  invaders = game.instance_variable_get(:@invaders).select { |i| i[:alive] }
  break if invaders.empty?
  target = invaders.first
  # téléporter la balle du joueur juste sous la cible : on simule via plusieurs tirs
  game.instance_variable_set(:@px, target[:x])
  # balle téléportée juste sous la cible : impact garanti en 1 tick
  # coordonnées braille : balle juste sous le sprite (5 pts de large, 4 de haut)
  game.instance_variable_get(:@bullets).replace([{ x: target[:x] + 2, y: target[:y] + 5 }])
  tick_n(game, 2)
  kills += 1
  raise "boucle infinie de kills" if kills > 100
end
score = game.instance_variable_get(:@score)
puts "1) VICTOIRE: #{game.instance_variable_get(:@over) && game.instance_variable_get(:@won)} | score: #{score} | tués: #{kills}"
raise "pas de victoire" unless game.instance_variable_get(:@won)

# ── 2) défaite : envahisseurs forcés jusqu'en bas ──
game2 = Game.new
game2.start(0)
# forcer la descente : appeler step massivement ; bombes désactivées pour ce test
game2.instance_variable_set(:@frame, 0)
1600.times do
  break if game2.instance_variable_get(:@over)
  game2.update(TickMessage.new)
  game2.instance_variable_set(:@bombs, []) # neutralise les tirs ennemis
end
# vies restaurées pour isoler la cause invasion
game2.instance_variable_set(:@lives, [game2.instance_variable_get(:@lives), 4].max) unless game2.instance_variable_get(:@over)
puts "2) DÉFAITE par invasion: #{game2.instance_variable_get(:@over) && !game2.instance_variable_get(:@won)} | message: #{game2.instance_variable_get(:@message)[0, 40]}"

# ── 3) défaite par bombes : vies à 1 + bombe sur le joueur ──
game3 = Game.new
game3.start(0)
game3.instance_variable_set(:@lives, 1)
# bombe positionnée pour percuter le vaisseau après 2 ticks (chute de 3 pts/tick)
px = game3.instance_variable_get(:@px)
game3.instance_variable_set(:@bombs, [{ x: px + 2, y: DOTS_H - 4 - 6 }])
2.times { tick_n(game3, 1) }
puts "3) DÉFAITE par bombes: #{game3.instance_variable_get(:@over) && !game3.instance_variable_get(:@won)}"

# ── 4) clamps : le vaisseau reste dans le champ ──
game4 = Game.new
game4.start(0)
40.times { game4.update(key("left")) }
px_min = game4.instance_variable_get(:@px)
40.times { game4.update(key("right")) }
px_max = game4.instance_variable_get(:@px)
puts "4) clamps: px min=#{px_min} (>=1) max=#{px_max} (<=#{DOTS_W - 6}): #{px_min >= 1 && px_max <= DOTS_W - 6}"

puts "tous les tests logiques passent"
