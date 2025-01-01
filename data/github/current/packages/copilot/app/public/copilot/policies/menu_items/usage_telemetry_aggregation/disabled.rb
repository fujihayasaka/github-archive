# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module MenuItems
      module UsageTelemetryAggregation
        class Disabled < Copilot::Policies::MenuItems::UsageTelemetryAggregation::Base
          STANDALONE_BUSINESS_DESCRIPTION = "Administrators won't have access to the feature"
          BUSINESS_DESCRIPTION = "All business and organization administrators won't have access to the feature"
          ORGANIZATION_DESCRIPTION = "Administrators of this organization won't have access to the feature"

          sig { override.returns(T::Boolean) }
          def checked?
            return @checked unless @checked.nil?

            telemetry_aggregation_disabled?
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
