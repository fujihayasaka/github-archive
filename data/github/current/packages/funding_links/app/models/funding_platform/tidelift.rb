# typed: strict
# frozen_string_literal: true

class FundingPlatform::Tidelift
  sig { returns String }
  def self.name
    "Tidelift"
  end

  sig { returns URI }
  def self.url
    URI("https://tidelift.com/funding/github/")
  end

  sig { returns Symbol }
  def self.key
    :tidelift
  end

  sig { returns String }
  def self.template_placeholder
    "# Replace with a single #{name} platform-name/package-name e.g., npm/babel"
  end
end
