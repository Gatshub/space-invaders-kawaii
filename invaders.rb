#!/usr/bin/env ruby
# frozen_string_literal: true

# Space Invaders kawaii — Ruby + Charm Ruby (bubbletea / lipgloss)
# Rendu en caractères braille : chaque caractère = 2x4 points, mouvements fluides.

require 'bundler/setup'
require 'bubbletea'
require 'lipgloss'

# ─── Couleurs adaptatives (clair / sombre) ──────────────────────────────────

ACCENT = Lipgloss::AdaptiveColor.new(light: '#D6488C', dark: '#FF9EC4')
OK     = Lipgloss::AdaptiveColor.new(light: '#1F7A4D', dark: '#7BD8A8')
KO     = Lipgloss::AdaptiveColor.new(light: '#B3243C', dark: '#FF7B8A')
MUTED  = Lipgloss::AdaptiveColor.new(light: '#8A7D8F', dark: '#9A8CA0')
SOFT   = Lipgloss::AdaptiveColor.new(light: '#6E5A75', dark: '#C9BBD1')

TITLE_STYLE  = Lipgloss::Style.new.bold(true).foreground(ACCENT)
BORDER_STYLE = Lipgloss::Style.new.border(:rounded).border_foreground(ACCENT).padding(0, 1)
PLAYER_STYLE = Lipgloss::Style.new.bold(true).foreground(ACCENT)
# une teinte par rangée d'envahisseurs
ROW_STYLES = [
  Lipgloss::Style.new.bold(true).foreground(OK),
  Lipgloss::Style.new.bold(true).foreground(ACCENT),
  Lipgloss::Style.new.bold(true).foreground(SOFT),
  Lipgloss::Style.new.bold(true).foreground(MUTED)
].freeze
BULLET_STYLE = Lipgloss::Style.new.bold(true).foreground(OK)
BOMB_STYLE   = Lipgloss::Style.new.bold(true).foreground(KO)
HUD_STYLE    = Lipgloss::Style.new.foreground(SOFT)
GOOD_STYLE   = Lipgloss::Style.new.bold(true).foreground(OK)
BAD_STYLE    = Lipgloss::Style.new.bold(true).foreground(KO)
MSG_STYLE    = Lipgloss::Style.new.bold(true).foreground(ACCENT)
HELP_STYLE   = Lipgloss::Style.new.faint(true)
PAW_STYLE    = Lipgloss::Style.new.foreground(ACCENT)
PLAIN_S      = Lipgloss::Style.new
MUTED_S      = Lipgloss::Style.new.foreground(MUTED)
SOFT_S       = Lipgloss::Style.new.bold(true).foreground(SOFT)

# ─── Niveaux ─────────────────────────────────────────────────────────────────

LEVELS = [
  { name: "facile",    rows: 3, cols: 6, speed: 4, bombs: 3, lives: 4 },
  { name: "moyen",     rows: 4, cols: 7, speed: 3, bombs: 5, lives: 3 },
  { name: "difficile", rows: 4, cols: 8, speed: 2, bombs: 8, lives: 2 }
].freeze

# Accélération : le tick de base, resserré au fil des kills (min 0.025 s)
TICK_BASE = 0.04
TICK_MIN  = 0.022

# Champ en points braille : chaque caractère = 2 colonnes × 4 lignes de points
DOTS_W = 88  # 44 caractères de large
DOTS_H = 60  # 15 caractères de haut

# ─── Sprites braille (liste de points [x, y] relatifs) ───────────────────────

INVADER_SPRITES = [
  # bouche ouverte / fermée — petit crabe 6x4 points
  [[0, 1], [1, 0], [2, 0], [3, 0], [4, 1], [0, 2], [4, 2], [1, 3], [3, 3]],
  [[0, 1], [1, 1], [2, 0], [3, 0], [4, 1], [0, 2], [4, 2], [1, 3], [2, 3], [3, 3]]
].freeze
SHIP_SPRITE = [[0, 3], [1, 2], [2, 0], [2, 1], [2, 2], [3, 2], [4, 3]].freeze

# Bunkers : 4 blocs immobiles (points braille), érodés par les impacts.
# Chaque bunker = 12 pts de large × 7 de haut, forme à toit plat.
BUNKER_W = 12
BUNKER_H = 7
BUNKER_COUNT = 4
BUNKER_Y = DOTS_H - 16

# ─── Braille : encodage d'une cellule 2x4 ────────────────────────────────────

BRAILLE_BASE = 0x2800
# disposition des points :
# 1 4
# 2 5
# 3 6
# 7 8
DOT_BIT = { [0, 0] => 1, [0, 1] => 2, [0, 2] => 4, [1, 0] => 8,
            [1, 1] => 16, [1, 2] => 32, [0, 3] => 64, [1, 3] => 128 }.freeze

def braille_char(dots)
  code = BRAILLE_BASE
  dots.each { |dx, dy| code += DOT_BIT.fetch([dx, dy], 0) }
  [code].pack("U")
end

# ─── Messages ────────────────────────────────────────────────────────────────

class TickMessage < Bubbletea::Message; end

# ─── Modèle ──────────────────────────────────────────────────────────────────

class Game
  include Bubbletea::Model

  attr_reader :menu, :level_idx

  def initialize
    @menu = true
    @level_idx = 0
    @width = 80
    @height = 24
    @paws = 0
    @bunkers_on = true
  end

  def init
    [self, schedule_tick]
  end

  def start(level_idx)
    lv = LEVELS[level_idx]
    @menu = false
    @level_idx = level_idx
    @lives = lv[:lives]
    @score = 0
    @px = DOTS_W / 2 - 2
    @bullets = []
    @bombs = []
    @dir = 1
    @frame = 0
    @over = false
    @won = false
    @message = "Défends la galaxie (๑˃ᴗ˂)ﻭ"
    @invaders = []
    lv[:rows].times do |r|
      lv[:cols].times do |c|
        @invaders << { row: r, col: c, x: 8 + c * 8, y: 2 + r * 7, alive: true }
      end
    end
    # bunkers : optionnels (bascule avec 'b' au menu)
    @bunkers = []
    return unless @bunkers_on
    span = DOTS_W / BUNKER_COUNT
    BUNKER_COUNT.times do |k|
      bx = k * span + (span - BUNKER_W) / 2
      dots = []
      BUNKER_H.times do |dy|
        BUNKER_W.times do |dx|
          # coins supérieurs biseautés + cavité centrale en bas (comme l'original)
          next if dy == 0 && (dx < 2 || dx >= BUNKER_W - 2)
          next if dy == 1 && (dx < 1 || dx >= BUNKER_W - 1)
          next if dy >= BUNKER_H - 2 && dx >= 4 && dx < 8
          dots << [bx + dx, BUNKER_Y + dy]
        end
      end
      @bunkers << { dots: dots }
    end
  end

  def schedule_tick
    # accélération progressive : le tick se resserre à mesure que la
    # formation fond (min TICK_MIN)
    progress = @over || @invaders.nil? ? 0 : alive_count.to_f / (@invaders.size.nonzero? || 1)
    delay = TICK_MIN + (TICK_BASE - TICK_MIN) * progress
    Bubbletea.tick(delay) { TickMessage.new } # ~25→45 fps
  end

  def alive_count
    @invaders&.count { |i| i[:alive] } || 0
  end

  # ── update ──

  def update(message)
    case message
    when Bubbletea::WindowSizeMessage
      @width = message.width
      @height = message.height
      [self, nil]
    when TickMessage
      @paws += 1 if @over && @won
      step unless @menu || @over
      [self, schedule_tick]
    when Bubbletea::KeyMessage
      handle_key(message)
    else
      [self, nil]
    end
  end

  def handle_key(message)
    key = message.to_s
    if @menu
      case key
      when "1", "2", "3"
        start(key.to_i - 1)
      when "down", "j", "right", "l"
        @level_idx = (@level_idx + 1) % LEVELS.size
      when "up", "k", "left", "h"
        @level_idx = (@level_idx - 1) % LEVELS.size
      when "b"
        @bunkers_on = !@bunkers_on
      when "enter", "space", " "
        start(@level_idx)
      when "q", "ctrl+c", "esc"
        return [self, Bubbletea.quit]
      end
      return [self, nil]
    end

    case key
    when "q", "ctrl+c"
      return [self, Bubbletea.quit]
    when "esc", "m"
      @menu = true
    when "n"
      start(@level_idx)
    when "left", "h"
      @px = [@px - 2, 1].max unless @over
    when "right", "l"
      @px = [@px + 2, DOTS_W - 6].min unless @over
    when "space", " ", "up", "w"
      shoot
    end
    [self, nil]
  end

  def shoot
    return if @over
    return unless @bullets.empty? # une balle à la fois, style classique
    @bullets << { x: @px + 2, y: DOTS_H - 5 }
    @message = "Petit ♡ parti !"
  end

  # ── simulation (tout en points braille) ──

  def invader_dots(inv)
    sprite = INVADER_SPRITES[@frame % 2]
    sprite.map { |dx, dy| [inv[:x] + dx, inv[:y] + dy] }
  end

  # impact sur un bunker : érode le point touché + ses voisins ; true si touché
  def bunker_hit!(x, y)
    @bunkers.each do |b|
      struck = b[:dots].select { |dx, dy| (dx - x).abs <= 1 && (dy - y).abs <= 1 }
      next if struck.empty?
      # érosion : retire l'impact + ses voisins directs
      sx = struck.map(&:first).sum / struck.size
      sy = struck.map(&:last).sum / struck.size
      b[:dots].reject! { |dx, dy| (dx - sx).abs <= 1 && (dy - sy).abs <= 1 }
      return true
    end
    false
  end

  def ship_dots
    SHIP_SPRITE.map { |dx, dy| [@px + dx, DOTS_H - 4 + dy] }
  end

  def step
    lv = LEVELS[@level_idx]
    @frame += 1

    # ── envahisseurs : 2 points latéraux tous les `speed` ticks ──
    if @frame % lv[:speed] == 0
      xs = @invaders.select { |i| i[:alive] }.map { |i| i[:x] }
      unless xs.empty?
        min_x = xs.min
        max_x = xs.max + 5 # largeur du sprite
        step = @dir * 2
        if (@dir.positive? && max_x + step > DOTS_W - 2) || (@dir.negative? && min_x + step < 2)
          @dir = -@dir
          @invaders.each { |i| i[:y] += 4 if i[:alive] } # descend d'une ligne braille
        else
          @invaders.each { |i| i[:x] += step if i[:alive] }
        end
        bottom = @invaders.select { |i| i[:alive] }.map { |i| i[:y] }.max
        if bottom >= DOTS_H - 12
          @over = true
          @won = false
          @message = "Ils ont débarqué... (´；ω；`)"
          return
        end
      end
    end

    # ── bombes ennemies ──
    if @frame % (lv[:bombs] * 3) == 0
      living = @invaders.select { |i| i[:alive] }
      shooter = living.sample
      @bombs << { x: shooter[:x] + 2, y: shooter[:y] + 4 } if shooter
    end
    @bombs.each { |b| b[:y] += 3 }
    ship = ship_dots
    # impact sur bunker
    @bombs.reject! do |b|
      bunker_hit!(b[:x], b[:y]) || bunker_hit!(b[:x], b[:y] - 1)
    end
    if @bombs.any? { |b| ship.any? { |sx, sy| (sx - b[:x]).abs <= 1 && (sy - b[:y]).abs <= 1 } }
      @bombs.clear
      @lives -= 1
      @message = "Aïe ! Il te reste #{@lives} ♡ (＞﹏＜)"
      if @lives <= 0
        @over = true
        @won = false
        @message = "Game over... (´；ω；`) [n] pour recommencer ♪"
      end
      return
    end
    @bombs.reject! { |b| b[:y] >= DOTS_H - 3 }

    # ── balle du joueur : 4 points par tick ──
    @bullets.each { |b| b[:y] -= 4 }
    @bullets.dup.each do |b|
      # impact sur bunker d'abord (les tirs se font absorber)
      if bunker_hit!(b[:x], b[:y]) || bunker_hit!(b[:x], b[:y] + 1)
        @bullets.delete(b)
        @message = "Ton ♡ s'est écrasé sur le barrage... (･_･;"
        next
      end
      hit = @invaders.find do |i|
        next false unless i[:alive]
        invader_dots(i).any? { |dx, dy| (dx - b[:x]).abs <= 1 && (dy - b[:y]).abs <= 1 }
      end
      next unless hit
      hit[:alive] = false
      @bullets.delete(b)
      @score += (4 - hit[:row]) * 10
      remaining = @invaders.count { |i| i[:alive] }
      if remaining.zero?
        @over = true
        @won = true
        @message = "GAGNÉ ! Galaxie sauvée !! ☆*:.｡.o(≧▽≦)o.｡.:*☆"
      else
        @message = "Un envahisseur de moins ! #{@score} pts ♪"
      end
    end
    @bullets.reject! { |b| b[:y] < 0 }
  end

  # ── vue ──

  def view
    if @menu
      center(menu_view)
    else
      center(game_view)
    end
  end

  def center(content)
    lines = content.chomp.split("\n")
    # mesurer SANS les codes d'échappement (les chaînes sont déjà stylées)
    visible = ->(l) { l.gsub(/\e\[[0-9;]*m/, "").length }
    max_w = lines.map { |l| visible.call(l) }.max || 0
    inner = [(@width - max_w) / 2, 0].max
    pad = " " * inner
    lines = lines.map { |l| pad + l }
    vpad = [(@height - lines.size) / 2, 0].max
    ([""] * vpad + lines).join("\n") + "\n"
  end

  def menu_view
    b = +""
    b << "\n"
    b << TITLE_STYLE.render(" ♡  S P A C E   I N V A D E R S  ♡ ")
    b << "\n\n"
    b << HUD_STYLE.render("Choisis ton niveau :")
    b << "\n\n"
    LEVELS.each_with_index do |lv, i|
      prefix = format("  [%d] ", i + 1)
      line = format("%-9s · %-11s · %d ♡", lv[:name], "#{lv[:rows]}x#{lv[:cols]}", lv[:lives])
      b << (i == @level_idx ? MSG_STYLE : HUD_STYLE).render(prefix + line) << "\n"
    end
    b << "\n"
    state = @bunkers_on ? GOOD_STYLE.render("on ") : BAD_STYLE.render("off")
    b << HUD_STYLE.render("  [b] bunkers : ") + state
    b << "\n"
    b << HELP_STYLE.render("↑↓ choisir · entrée jouer · 1/2/3 direct · b bunkers · q quitter")
    b << "\n"
    b
  end

  def hud
    hearts = ("♡ " * [@lives, 0].max).strip
    HUD_STYLE.render("score : #{@score}") + "   " +
      HUD_STYLE.render("niveau : #{LEVELS[@level_idx][:name]}") + "   " +
      GOOD_STYLE.render("vies : #{hearts}")
  end

  # rendu : matrice de points → caractères braille colorés.
  # Perf : on groupe les cellules contiguës de même style en un seul
  # .render() (le binding Go coûte ~0,4 ms par appel → 660 appels/frame
  # = 285 ms ; groupé, on tombe à quelques ms).
  def game_view
    cells = Array.new(DOTS_H / 4) { Array.new(DOTS_W / 2) { [[], PLAIN_S] } }

    draw = lambda do |dots, style|
      dots.each do |x, y|
        cy, cx = y / 4, x / 2
        next unless cy.between?(0, cells.size - 1) && cx.between?(0, cells[0].size - 1)
        cell = cells[cy][cx]
        cell[0] << [x % 2, y % 4]
        cell[1] = style
      end
    end

    @invaders.each do |i|
      next unless i[:alive]
      draw.call(invader_dots(i), ROW_STYLES[i[:row] % ROW_STYLES.size])
    end
    @bunkers.each { |b| draw.call(b[:dots], SOFT_S) }
    draw.call(ship_dots, PLAYER_STYLE) unless @over && !@won
    @bullets.each { |b| draw.call([[b[:x], b[:y]], [b[:x], b[:y] + 1]], BULLET_STYLE) if b[:y] >= 0 && b[:y] < DOTS_H }
    @bombs.each { |b| draw.call([[b[:x], b[:y]], [b[:x], b[:y] + 1]], BOMB_STYLE) if b[:y] >= 0 && b[:y] < DOTS_H }

    field = cells.map do |row|
      row_cells = row.map { |dots, style| [dots.empty? ? "⠀" : braille_char(dots), style] }
      # fusionner les runs de même style ; les runs PLAIN (vides) ne passent
      # PAS par le binding Go (render d'un style sans attributs = coût par
      # appel inutile) : chaîne brute.
      out = +""
      run_char = +""; run_style = row_cells[0][1]
      flush = lambda do
        out << (run_style == PLAIN_S ? run_char : run_style.render(run_char))
      end
      row_cells.each do |ch, st|
        if st == run_style
          run_char << ch
        else
          flush.call
          run_char = +"#{ch}"; run_style = st
        end
      end
      flush.call
      out
    end

    b = +""
    b << TITLE_STYLE.render(" ♡  S P A C E   I N V A D E R S  ♡ ")
    b << "\n"
    b << hud
    b << "\n\n"
    b << BORDER_STYLE.render(field.join("\n"))
    b << "\n\n"
    if @over
      b << (@won ? GOOD_STYLE : BAD_STYLE).render(@message)
      b << "\n"
      if @won
        b << PAW_STYLE.render("🐾 ♡ " * (1 + [@paws, 6].min)) << "\n"
      end
      b << HELP_STYLE.render("[n] rejouer · [m] menu · [q] quitter")
    else
      b << MSG_STYLE.render(@message)
      b << "\n\n"
      b << HELP_STYLE.render("←→ bouger · espace tirer · n rejouer · m menu · q quitter")
    end
    b << "\n"
    b
  end
end

if $PROGRAM_NAME == __FILE__
  Bubbletea.run(Game.new, alt_screen: true)
end
