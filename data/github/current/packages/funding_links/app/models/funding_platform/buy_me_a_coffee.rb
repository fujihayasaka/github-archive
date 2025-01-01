# typed: strict
# frozen_string_literal: true

class FundingPlatform::BuyMeACoffee
  extend T::Sig

  sig { returns String }
  def self.name
    "Buy Me a Coffee"
  end

  sig { returns URI }
  def self.url
    URI("https://buymeacoffee.com/")
  end

  sig { returns Symbol }
  def self.key
    :buy_me_a_coffee
  end

  sig { returns String }
  def self.template_placeholder
    "# Replace with a single #{name} username"
  end
end
