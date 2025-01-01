# typed: strict
# frozen_string_literal: true

module SecretScanning
  module Errors
    class UnableToReportToken < StandardError
      sig { params(msg: String, repo: Integer, alert_number: Integer).void }
      def initialize(msg, repo, alert_number)
        @repo = repo
        @alert_number = alert_number
        @msg = msg
      end

      sig { returns(String) }
      def message
        "unable to report for #{@repo}:#{@alert_number} with reason #{@msg}"
      end

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def payload
        { repo: @repo, alert: @alert_number, msg: @msg }
      end
    end
  end
end
