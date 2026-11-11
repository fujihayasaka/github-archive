# typed: true
# frozen_string_literal: true

module RulesInsights
  module Twirp
    class Error < StandardError; end
    class PermissionDenied < Error; end
    class Unavailable < Error; end
    class Internal < Error; end

    sig { returns(RulesClient) }
    def self.rules_client
      @rules_client ||= RulesClient.new
    end
  end
end
