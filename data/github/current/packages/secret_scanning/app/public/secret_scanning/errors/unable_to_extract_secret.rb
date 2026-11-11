# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module SecretScanning
  module Errors
    class UnableToExtractSecret < StandardError
      def initialize(repo, alert)
        @repo = repo
        @alert = alert
      end

      def message
        "unable to extract raw secret from token #{@repo}:#{@alert}"
      end

      def payload
        { repo: @repo, alert: @alert }
      end
    end
  end
end
