# typed: strict
# frozen_string_literal: true

class FundingPlatform::ThanksDev
  extend T::Sig

  sig { returns String }
  def self.name
    "thanks.dev"
  end

  sig { returns URI }
  def self.url
    URI("https://thanks.dev/")
  end

  sig { returns Symbol }
  def self.key
    :thanks_dev
  end

  sig { returns String }
  def self.template_placeholder
    "# Replace with a single #{name} username"
  end
end
