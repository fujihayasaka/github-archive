# typed: strict
# frozen_string_literal: true

class FundingPlatform::Polar
  sig { returns String }
  def self.name
    "Polar"
  end

  sig { returns URI }
  def self.url
    URI("https://polar.sh/")
  end

  sig { returns Symbol }
  def self.key
    :polar
  end

  sig { returns String }
  def self.template_placeholder
    "# Replace with a single #{name} username"
  end
end
