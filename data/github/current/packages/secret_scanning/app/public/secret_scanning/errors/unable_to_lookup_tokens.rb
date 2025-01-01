# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module SecretScanning
  module Errors
    class UnableToLookupTokens < StandardError
      def initialize(repo, alert)
        @repo = repo
        @alert = alert
      end

      def message
        "unable to look up tokens for #{@repo}:#{@alert}"
      end

      def payload
        { repo: @repo, alert: @alert }
      end
    end
  end
end
