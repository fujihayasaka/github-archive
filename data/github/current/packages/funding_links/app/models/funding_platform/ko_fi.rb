# typed: strict
# frozen_string_literal: true

class FundingPlatform::KoFi
  sig { returns String }
  def self.name
    "Ko-fi"
  end

  sig { returns URI }
  def self.url
    URI("https://ko-fi.com/")
  end

  sig { returns Symbol }
  def self.key
    :ko_fi
  end

  sig { returns String }
  def self.template_placeholder
    "# Replace with a single #{name} username"
  end
end
