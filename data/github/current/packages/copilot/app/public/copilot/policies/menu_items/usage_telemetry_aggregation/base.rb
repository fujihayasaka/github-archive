# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module MenuItems
      module UsageTelemetryAggregation
        class Base < Copilot::Policies::MenuItems::Base
          abstract!

          sig { override.returns(T.any(Copilot::Organization, Copilot::Business)) }
          attr_reader :copilot_configurable

          sig { params(copilot_configurable: T.any(Copilot::Organization, Copilot::Business), type: String, checked: T.nilable(T::Boolean)).void }
          def initialize(copilot_configurable:, type: "submit", checked: nil)
            super(copilot_configurable: copilot_configurable, type: type, checked: checked)
            @copilot_configurable = copilot_configurable
          end

          private

          delegate :telemetry_aggregation_enabled?, to: :copilot_configurable

          sig { override.returns(String) }
          def name
            "copilot_telemetry_aggregation"
          end

          sig { returns(T::Boolean) }
          def telemetry_aggregation_disabled?
            if copilot_configurable.__getobj__.is_a?(::Business)
              return T.cast(copilot_configurable, Copilot::Business).telemetry_aggregation_disabled?
            end

            !copilot_configurable.telemetry_aggregation_enabled?
          end
        end
      end
    end
  end
end
