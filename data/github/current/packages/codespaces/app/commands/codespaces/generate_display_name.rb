# typed: true
# frozen_string_literal: true

module Codespaces
  class GenerateDisplayName < Command
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
      glorious
      glowing
      humble
      ideal
      improved
      jubilant
      laughing
      legendary
      literate
      miniature
      musical
      obscure
      ominous
      opulent
      orange
      organic
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
      zany
    ].freeze

    NOUNS = %w[
      acorn
      adventure
      barnacle
      bassoon
      broccoli
      capybara
      carnival
      chainsaw
      cod
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
      goldfish
      guacamole
      guide
      halibut
      happiness
      invention
      journey
      lamp
      meme
      memory
      orbit
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
      trout
      umbrella
      waddle
      waffle
      winner
      xylophone
      yodel
      zebra
    ].freeze

    SPOOKY_ADJECTIVES = %w[
      accursed
      ancient
      alarming
      broken
      caverned
      chilling
      crowded
      cold
      damp
      dark
      disreputable
      dreadful
      fearful
      frightening
      fearsome
      filthy
      foul
      ghastly
      gloomy
      gory
      grim
      gruesome
      hallowed
      haunted
      hidden
      horrible
      infamous
      lifeless
      lonely
      miserable
      moonlit
      mysterious
      neglected
      nightmarish
      noxious
      nasty
      paranormal
      petrifying
      poisonous
      possessed
      repulsive
      savage
      scary
      secret
      shadowy
      shady
      shocking
      sinister
      solitary
      spooky
      squalid
      supernatural
      spindly
      spidery
      terrible
      uncanny
      unearthly
      unhallowed
      weary
      wild
      wretched
    ].freeze

    SPOOKY_NOUNS = %w[
      apparition
      bat
      broomstick
      cackle
      cadaver
      cape
      casket
      cauldron
      cemetery
      cobweb
      coffin
      corpse
      crematorium
      crypt
      fishsticks
      ghost
      goblin
      gravestone
      graveyard
      haunting
      hex
      hobgoblin
      incantation
      mausoleum
      monster
      mummy
      orb
      owl
      phantasm
      phantom
      poltergeist
      seance
      shadow
      skeleton
      skull
      sorcery
      specter
      spell
      spider
      spirit
      superstition
      toad
      tomb
      troll
      vampire
      wand
      werewolf
      wizard
      wraith
      zombie
    ].freeze

    sig { override.returns(String) }
    def perform
      return perform_spooky if spooky_time?

      prefix = rand < 0.25 ? "space " : ""
      "#{ADJECTIVES.sample} #{prefix}#{NOUNS.sample}"
    end

    sig { returns(T::Boolean) }
    private def spooky_time?
      today = DateTime.current
      today.month == 10 && today.day.in?(25..31)
    end

    sig { returns(String) }
    private def perform_spooky
      prefix = rand < 0.25 ? "spooky " : ""
      "#{SPOOKY_ADJECTIVES.sample} #{prefix}#{SPOOKY_NOUNS.sample}"
    end
  end
end
