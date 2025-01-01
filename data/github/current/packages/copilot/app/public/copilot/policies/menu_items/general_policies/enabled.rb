# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module MenuItems
      module GeneralPolicies
        class Enabled < Copilot::Policies::MenuItems::GeneralPolicies::Base
          STANDALONE_BUSINESS_DESCRIPTION = "Members will have access to the feature"
          BUSINESS_DESCRIPTION = "All organizations will have access to the feature"
          REFRESH_BUSINESS_DESCRIPTION = "All organizations and all users have access to this feature. It cannot be disabled at the organization level."
          ORGANIZATION_DESCRIPTION = "Members with a Copilot license will have access to the feature"
          USER_DESCRIPTION = "You will have access to the feature"

          sig { override.returns(String) }
          def label
            "Enabled"
          end

          sig { override.returns(String) }
          def description
            if standalone_business?
              STANDALONE_BUSINESS_DESCRIPTION
            elsif policies_refresh_business?
              REFRESH_BUSINESS_DESCRIPTION
            elsif business?
              BUSINESS_DESCRIPTION
            elsif organization?
              ORGANIZATION_DESCRIPTION
            elsif user?
              USER_DESCRIPTION
            else
              ORGANIZATION_DESCRIPTION
            end
          end
        end
      end
    end
  end
end
