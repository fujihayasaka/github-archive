# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module MenuItems
      module CopilotForDotcom
        class Enabled < Copilot::Policies::MenuItems::CopilotForDotcom::Base
          BUSINESS_DESCRIPTION = "All organizations will have access to the features."
          ORGANIZATION_DESCRIPTION = "Members with a Copilot license will have access to the features."

          private

          sig { override.returns(T::Boolean) }
          def checked?
            copilot_for_dotcom_enabled?
          end

          sig { override.returns(String) }
          def description
            business? ? BUSINESS_DESCRIPTION : ORGANIZATION_DESCRIPTION
          end
        end
      end
    end
  end
end
