# typed: strict
# frozen_string_literal: true

module SecretScanning
  module Models
    class ValidationSupport
      sig { returns(T::Boolean) }
      attr_reader :validity_checks_supported, :on_demand_checks_supported
      sig { params(on_demand_checks_supported: T::Boolean).void }
      attr_writer :on_demand_checks_supported

      sig { params(validity_checks_supported: T::Boolean, on_demand_checks_supported: T::Boolean).void }
      def initialize(validity_checks_supported:, on_demand_checks_supported:)
        @validity_checks_supported = validity_checks_supported
        @on_demand_checks_supported = on_demand_checks_supported
      end
    end
  end
end
