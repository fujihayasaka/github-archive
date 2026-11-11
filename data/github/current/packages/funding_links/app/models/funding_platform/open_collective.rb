# typed: strict
# frozen_string_literal: true

class FundingPlatform::OpenCollective
  sig { returns String }
  def self.name
    "Open Collective"
  end

  sig { returns URI }
  def self.url
    URI("https://opencollective.com/")
  end

  sig { returns Symbol }
  def self.key
    :open_collective
  end

  sig { returns String }
  def self.template_placeholder
    "# Replace with a single #{name} username"
  end
end
