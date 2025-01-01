# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module MenuItems
      module EaUserFallback
        class Enabled < Copilot::Policies::MenuItems::GeneralPolicies::Enabled
          DESCRIPTION = "Policies that are set to 'No policy' are enabled for enterprise-assigned users."

          sig { override.returns(String) }
          def description
            DESCRIPTION
          end
        end
      end
    end
  end
end
