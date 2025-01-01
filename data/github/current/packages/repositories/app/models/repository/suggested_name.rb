# typed: true
# frozen_string_literal: true

class Repository::SuggestedName
  ADJECTIVES = %w[
    animated
    automatic
    bookish
    bug-free
    cautious
    congenial
    crispy
    cuddly
    curly
    didactic
    effective
    expert
    fantastic
    fictional
    fluffy
    friendly
    fuzzy
    glowing
    ideal
    improved
    jubilant
    laughing
    legendary
    literate
    miniature
    musical
    potential
    probable
    psychic
    redesigned
    refactored
    reimagined
    scaling
    shiny
    silver
    solid
    special
    studious
    stunning
    sturdy
    super
    super-duper
    supreme
    symmetrical
    turbo
    ubiquitous
    upgraded
    urban
    verbose
    vigilant
  ].freeze

  NOUNS = %w[
    adventure
    barnacle
    bassoon
    broccoli
    carnival
    chainsaw
    computing-machine
    couscous
    disco
    dollop
    doodle
    engine
    enigma
    eureka
    fiesta
    fishstick
    fortnight
    funicular
    garbanzo
    giggle
    goggles
    guacamole
    guide
    happiness
    invention
    journey
    lamp
    meme
    memory
    palm-tree
    pancake
    parakeet
    potato
    robot
    rotary-phone
    sniffle
    spoon
    spork
    succotash
    system
    telegram
    train
    tribble
    umbrella
    waddle
    waffle
    winner
  ].freeze

  # Public: Creates a fun suggested name for users
  #
  # @return [String] the suggested name
  sig { returns(::String) }
  def self.generate
    prefix = rand < 0.25 ? "octo-" : ""
    "#{ADJECTIVES.sample}-#{prefix}#{NOUNS.sample}"
  end
end
