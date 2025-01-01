# typed: true
# frozen_string_literal: true

module Sponsors
  # Public: Utility to filter out profanity from user-given metadata passed along from sponsors to maintainers when a sponsorship is made.
  #
  # You probably don't want to use this class to check for profanity.
  # Hamzo is the go-to solution for this purpose <https://github.com/github/hamzo>
  # You should check there is a specific reason not to use Hamzo before using or
  # extending this class.
  class ProfaneLanguageCheck
    # Public: Check if a given string includes profanity.
    sig { params(input: String).returns(T::Boolean) }
    def self.call(input)
      new.contains_harassing_language?(input)
    end

    sig { returns Regexp }
    def self.blocked_term_regex
      /#{Regexp.union(BLOCKED_TERMS).source}/i
    end

    # List taken from https://github.com/github/hamzo/pull/1335
    BLOCKED_TERMS = %w(
      1488
      88
      aryan
      chink
      crip
      cunt
      dyke
      fag
      faggot
      family-fuck
      family-nudism
      gamergate
      golliwog
      gook
      hitler
      incest
      inzst
      isis
      jailbait
      jihad
      keep-it-in-the-family
      kike
      kkk
      n1gg3r
      n1gga
      n1gger
      nazi
      nazis
      nazism
      nigg3r
      nigga
      niggah
      niggar
      nigger
      niggor
      niggr
      nigguh
      paki
      pepe
      pickaninnie
      pickaninny
      pre-teens
      pussie
      pussy
      raghead
      retard
      shemale
      stormfront
      tits
      titt
      trannie
      tranny
      twat
      underage
      wetback
      white-genocide
      white-power
      white-pride
      whore
    ).freeze

    sig { params(string: String).returns(T::Boolean) }
    def contains_harassing_language?(string)
      return false if string.blank?
      !!(string =~ self.class.blocked_term_regex)
    end
  end
end
