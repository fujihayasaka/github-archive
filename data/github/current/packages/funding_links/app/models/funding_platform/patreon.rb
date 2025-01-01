# typed: strict
# frozen_string_literal: true

class FundingPlatform::Patreon
  sig { returns String }
  def self.name
    "Patreon"
  end

  sig { returns URI }
  def self.url
    URI("https://patreon.com/")
  end

  sig { returns Symbol }
  def self.key
    :patreon
  end

  sig { returns String }
  def self.template_placeholder
    "# Replace with a single #{name} username"
  end
end
