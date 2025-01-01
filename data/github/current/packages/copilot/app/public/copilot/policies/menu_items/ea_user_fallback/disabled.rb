# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module MenuItems
      module EaUserFallback
        class Disabled < Copilot::Policies::MenuItems::GeneralPolicies::Disabled
          DESCRIPTION = "Policies that are set to 'No policy' are disabled for enterprise-assigned users."

          sig { override.returns(String) }
          def description
            DESCRIPTION
          end
        end
      end
    end
  end
end
