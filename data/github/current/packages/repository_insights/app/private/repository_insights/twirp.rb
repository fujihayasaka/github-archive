# typed: true
# frozen_string_literal: true

module RepositoryInsights
  module Twirp
    class Error < StandardError; end
    class PermissionDenied < Error; end
    class Unavailable < Error; end
    class Internal < Error; end

    sig { returns(InsightsClient) }
    def self.insights_client
      @insights_client ||= InsightsClient.new
    end
  end
end
