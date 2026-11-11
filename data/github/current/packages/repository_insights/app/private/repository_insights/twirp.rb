# typed: true
# frozen_string_literal: true

module RepositoryInsights
  module Twirp
    class Error < StandardError; end
    class PermissionDenied < Error; end
    class Unavailable < Error; end
    class Internal < Error; end

    sig { returns(TrafficClient) }
    def self.traffic_client
      @traffic_client ||= TrafficClient.new
    end
  end
end
