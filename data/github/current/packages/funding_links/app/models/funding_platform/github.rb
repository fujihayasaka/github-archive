# typed: strict
# frozen_string_literal: true

class FundingPlatform::GitHub
  extend T::Sig

  sig { returns String }
  def self.name
    "GitHub"
  end

  sig { returns URI }
  def self.url
    URI("https://github.com/")
  end

  sig { returns Symbol }
  def self.key
    :github
  end

  sig { returns String }
  def self.template_placeholder
    "# Replace with up to 4 GitHub Sponsors-enabled usernames e.g., [user1, user2]"
  end
end
