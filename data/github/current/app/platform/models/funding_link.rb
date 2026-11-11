# typed: true
# frozen_string_literal: true

class Platform::Models::FundingLink
  attr_reader :repository, :platform, :url

  def initialize(repository:, platform:, url:)
    @repository = repository
    @platform   = platform
    @url        = url
  end
end
