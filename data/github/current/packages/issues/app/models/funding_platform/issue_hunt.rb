# typed: true
# frozen_string_literal: true

class FundingPlatform::IssueHunt
  def self.name
    "IssueHunt"
  end

  def self.url
    URI("https://issuehunt.io/r/")
  end

  def self.key
    :issuehunt
  end

  def self.template_placeholder
    "# Replace with a single #{name} username"
  end
end
