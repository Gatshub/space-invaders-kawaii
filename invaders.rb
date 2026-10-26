#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "bubbletea"
require "lipgloss"

# ─── Couleurs adaptatives (clair / sombre) ──────────────────────────────────

ACCENT = Lipgloss::AdaptiveColor.new(light: "#D6488C", dark: "#FF9EC4")
OK     = Lipgloss::AdaptiveColor.new(light: "#1F7A4D", dark: "#7BD8A8")
KO     = Lipgloss::AdaptiveColor.new(light: "#B3243C", dark: "#FF7B8A")
MUTED  = Lipgloss::AdaptiveColor.new(light: "#8A7D8F", dark: "#9A8CA0")
SOFT   = Lipgloss::AdaptiveColor.new(light: "#6E5A75", dark: "#C9BBD1")

TITLE_STYLE = Lipgloss::Style.new.bold(true).foreground(ACCENT)
BORDER_STYLE = Lipgloss::Style.new.border(:rounded).border_foreground(ACCENT).padding(0, 1)
PLAYER_STYLE = Lipgloss::Style.new.bold(true).foreground(ACCENT)
INVADER_STYLES = [SOFT, ACCENT, MUTED].map do |c|
  Lipgloss::Style.new.bold(true).foreground(c)
end.freeze
BULLET_STYLE = Lipgloss::Style.new.bold(true).foreground(OK)
BOMB_STYLE   = Lipgloss::Style.new.bold(true).foreground(KO)
HUD_STYLE    = Lipgloss::Style.new.foreground(SOFT)
GOOD_STYLE   = Lipgloss::Style.new.bold(true).foreground(OK)
BAD_STYLE    = Lipgloss::Style.new.bold(true).foreground(KO)
MSG_STYLE    = Lipgloss::Style.new.bold(true).foreground(ACCENT)
HELP_STYLE   = Lipgloss::Style.new.faint(true)
PAW_STYLE    = Lipgloss::Style.new.foreground(ACCENT)

# ─── Niveaux ─────────────────────────────────────────────────────────────────

LEVELS = [
  { name: "facile",    rows: 3, cols: 6, speed: 6, bombs: 3, lives: 4 },
  { name: "moyen",     rows: 4, cols: 7, speed: 4, bombs: 5, lives: 3 },
  { name: "difficile", rows: 4, cols: 8, speed: 3, bombs: 8, lives: 2 }
].freeze

FIELD_W = 44
FIELD_H = 16

# ─── Messages de tick ────────────────────────────────────────────────────────

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
    @px = FIELD_W / 2
    @bullets = []
    @bombs = []
    @dir = 1
    @frame = 0
    @over = false
    @won = false
    @message = "Défends la galaxie (๑˃ᴗ˂)ﻭ"
    # formation d'envahisseurs : chaque case = {row:, col:, x:, y:, alive:}
    @invaders = []
    lv[:rows].times do |r|
      lv[:cols].times do |c|
        @invaders << { row: r, col: c, x: 6 + c * 4, y: 2 + r * 2, alive: true }
      end
    end
  end

  def schedule_tick
    Bubbletea.tick(0.09) { TickMessage.new }
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
      @px = [@px - 2, 1].max
      @message = "Esquive ♪" if @over
    when "right", "l"
      @px = [@px + 2, FIELD_W - 2].min
      @message = "Esquive ♪" if @over
    when "space", " ", "up", "w"
      shoot
    end
    [self, nil]
  end

  def shoot
    return if @over
    # une seule balle du joueur à l'écran (style classique, plus stratégique)
    if @bullets.empty?
      @bullets << { x: @px, y: FIELD_H - 2 }
      @message = "Petit ♡ parti !"
    end
  end

  def step
    lv = LEVELS[@level_idx]
    @frame += 1

    # ── envahisseurs : un pas latéral tous les `speed` ticks ──
    if @frame % lv[:speed] == 0
      xs = @invaders.select { |i| i[:alive] }.map { |i| i[:x] }
      unless xs.empty?
        min_x, max_x = xs.min, xs.max
        step = @dir * 2
        edge = step.positive? ? max_x + step > FIELD_W - 4 : min_x + step < 1
        if edge
          @dir = -@dir
          @invaders.each { |i| i[:alive] and i[:y] += 1 }
        else
          @invaders.each { |i| i[:alive] and i[:x] += step }
        end
        # ont-ils atteint le bas ?
        bottom = @invaders.select { |i| i[:alive] }.map { |i| i[:y] }.max
        if bottom >= FIELD_H - 2
          @over = true
          @won = false
          @message = "Ils ont débarqué... (´；ω；`)"
          return
        end
      end
    end

    # ── bombes ennemies ──
    if @frame % (lv[:bombs] * 2) == 0
      living = @invaders.select { |i| i[:alive] }
      shooter = living.sample
      @bombs << { x: shooter[:x], y: shooter[:y] + 1 } if shooter
    end
    @bombs.each { |b| b[:y] += 1 }
    @bombs.reject! { |b| b[:y] >= FIELD_H - 1 }
    if @bombs.any? { |b| (b[:x] - @px).abs <= 1 && b[:y] >= FIELD_H - 2 }
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

    # ── balle du joueur ──
    @bullets.each { |b| b[:y] -= 1 }
    # collision avec un envahisseur
    @bullets.dup.each do |b|
      hit = @invaders.find { |i| i[:alive] && (i[:x] - b[:x]).abs <= 1 && (i[:y] - b[:y]).abs <= 0 }
      next unless hit
      hit[:alive] = false
      @bullets.delete(b)
      @score += (3 - hit[:row]) * 10
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

  # ── view ──

  def view
    if @menu
      center(menu_view)
    else
      center(game_view)
    end
  end

  def center(content)
    lines = content.chomp.split("\n")
    max_w = lines.map { |l| l.length }.max || 0
    inner = [(@width - max_w) / 2, 0].max
    outer_pad = " " * inner
    lines = lines.map { |l| outer_pad + l }
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
      line = format("%-9s · %dx%d envahisseurs · %d ♡", lv[:name], lv[:rows], lv[:cols], lv[:lives])
      line = if i == @level_idx
               MSG_STYLE.render(prefix + line)
             else
               HUD_STYLE.render(prefix + line)
             end
      b << line << "\n"
    end
    b << "\n"
    b << HELP_STYLE.render("↑↓ choisir · entrée jouer · 1/2/3 direct · q quitter")
    b << "\n"
    b
  end

  def hud
    lv = LEVELS[@level_idx]
    hearts = ("♡ " * [@lives, 0].max).strip
    hearts = "— " * 0 if @lives <= 0
    HUD_STYLE.render("score : #{@score}") + "   " +
      HUD_STYLE.render("niveau : #{lv[:name]}") + "   " +
      GOOD_STYLE.render("vies : #{hearts}")
  end

  def game_view
    # grille de cellules {char, style} pour colorer chaque élément
    grid = Array.new(FIELD_H) { Array.new(FIELD_W) { { char: " ", style: PLAIN_S } } }

    # envahisseurs (animation : bouche ouverte/fermée), colorés par rangée
    open_mouth = (@frame / 2) % 2 == 0
    @invaders.each do |i|
      next unless i[:alive]
      style = INVADER_STYLES[i[:row] % INVADER_STYLES.size]
      glyph = open_mouth ? "v" : "V"
      grid[i[:y]][i[:x] - 1] = { char: "(", style: MUTED_S }
      grid[i[:y]][i[:x]] = { char: glyph, style: style }
      grid[i[:y]][i[:x] + 1] = { char: ")", style: MUTED_S }
    end
    # balle(s) du joueur
    @bullets.each { |b| grid[b[:y]][b[:x]] = { char: "♡", style: BULLET_S } if b[:y] >= 0 }
    # bombes
    @bombs.each { |b| grid[b[:y]][b[:x]] = { char: "*", style: BOMB_S } if b[:y] >= 0 }
    # vaisseau
    grid[FIELD_H - 1][@px - 1] = { char: "/", style: PLAYER_S }
    grid[FIELD_H - 1][@px] = { char: "^", style: PLAYER_S }
    grid[FIELD_H - 1][@px + 1] = { char: "\\", style: PLAYER_S }

    b = +""
    b << TITLE_STYLE.render(" ♡  S P A C E   I N V A D E R S  ♡ ")
    b << "\n"
    b << hud
    b << "\n\n"

    field = grid.map do |row|
      row.map { |cell| cell[:style].render(cell[:char]) }.join
    end

    b << BORDER_STYLE.render(field.join("\n"))
    b << "\n\n"
    if @over
      b << (@won ? GOOD_STYLE : BAD_STYLE).render(@message)
      b << "\n"
      if @won
        b << PAW_STYLE.render("🐾 ♡ " * (1 + [@paws, 6].min))
        b << "\n"
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

  # styles desecours (références stables dans la boucle de rendu)
  PLAIN_S   = Lipgloss::Style.new
  MUTED_S   = Lipgloss::Style.new.foreground(MUTED)
  BULLET_S  = BULLET_STYLE
  BOMB_S    = BOMB_STYLE
  PLAYER_S  = PLAYER_STYLE
end

if $PROGRAM_NAME == __FILE__
  Bubbletea.run(Game.new, alt_screen: true)
end
