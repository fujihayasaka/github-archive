# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module MenuItems
      module CopilotForDotcom
        class Disabled < Copilot::Policies::MenuItems::CopilotForDotcom::Base
          BUSINESS_DESCRIPTION = "Organizations won’t have access to the features."
          ORGANIZATION_DESCRIPTION = "Members of this organization won’t have access to the features."

          private

          sig { override.returns(T::Boolean) }
          def checked?
            if business?
              copilot_for_dotcom_disabled?
            else
              copilot_for_dotcom_disabled? || copilot_for_dotcom_no_policy? || (!copilot_for_dotcom_enabled? && !copilot_for_dotcom_disabled?)
            end
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
