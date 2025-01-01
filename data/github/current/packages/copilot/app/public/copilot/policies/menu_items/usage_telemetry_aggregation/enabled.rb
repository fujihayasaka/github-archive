# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module MenuItems
      module UsageTelemetryAggregation
        class Enabled < Copilot::Policies::MenuItems::UsageTelemetryAggregation::Base
          STANDALONE_BUSINESS_DESCRIPTION = "Administrators will have access to the feature"
          BUSINESS_DESCRIPTION = "All organization administrators will have access to the feature"
          ORGANIZATION_DESCRIPTION = "Administrators of this organization will have access to the feature"

          sig { override.returns(T::Boolean) }
          def checked?
            return @checked unless @checked.nil?

            if business?
              @copilot_configurable.usage_telemetry_api == "enabled"
            else
              telemetry_aggregation_enabled?
            end
          end

          private

          sig { override.returns(String) }
          def description
            if standalone_business?
              STANDALONE_BUSINESS_DESCRIPTION
            elsif business?
              BUSINESS_DESCRIPTION
            else
              ORGANIZATION_DESCRIPTION
            end
          end
        end
      end
    end
  end
end
