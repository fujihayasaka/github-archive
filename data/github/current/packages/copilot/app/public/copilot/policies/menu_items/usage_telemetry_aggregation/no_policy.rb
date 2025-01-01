# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module MenuItems
      module UsageTelemetryAggregation
        class NoPolicy < Copilot::Policies::MenuItems::UsageTelemetryAggregation::Base
          DESCRIPTION = "Each of your organizations will be able to set their own policy"


          sig { override.returns(Copilot::Business) }
          attr_reader :copilot_configurable

          sig { params(copilot_configurable: Copilot::Business, type: String, checked: T.nilable(T::Boolean)).void }
          def initialize(copilot_configurable:, type: "submit", checked: nil)
            super(copilot_configurable: copilot_configurable, type: type, checked: checked)
            @copilot_configurable = copilot_configurable
          end

          sig { override.returns(T::Boolean) }
          def render?
            @copilot_configurable.__getobj__.is_a?(::Business) && !standalone_business?
          end

          sig { override.returns(T::Boolean) }
          def checked?
            return @checked unless @checked.nil?

            @copilot_configurable.telemetry_aggregation_no_policy?
          end

          private

          sig { override.returns(String) }
          def description
            DESCRIPTION
          end
        end
      end
    end
  end
end
