# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module SecretScanning
  module Errors
    class UnableToResolveToken < StandardError
      def initialize(msg, repo, alert)
        @repo = repo
        @alert = alert
        @msg = msg
      end

      def message
        "unable to resolve for #{@repo}:#{@alert} with reason #{@msg}"
      end

      def payload
        { repo: @repo, alert: @alert, msg: @msg }
      end
    end
  end
end
