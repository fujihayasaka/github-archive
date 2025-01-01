# typed: strict
# frozen_string_literal: true

class FundingPlatform::Liberapay
  extend T::Sig

  sig { returns String }
  def self.name
    "Liberapay"
  end

  sig { returns URI }
  def self.url
    URI("https://liberapay.com/")
  end

  sig { returns Symbol }
  def self.key
    :liberapay
  end

  sig { returns String }
  def self.template_placeholder
    "# Replace with a single #{name} username"
  end
end
