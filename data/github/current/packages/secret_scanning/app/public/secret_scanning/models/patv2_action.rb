# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module SecretScanning
  module Models
    class Patv2Action
      attr_reader :action, :request_method, :target, :target_type

      sig do
        params(
          action: String,
          request_method: String,
          target: String,
          target_type: Symbol
        ).void
      end
      def initialize(action, request_method, target, target_type)
        @action = action
        @request_method = request_method
        @target = target
        @target_type = target_type
      end
    end
  end
end
