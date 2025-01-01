# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module MenuItems
      module GeneralPolicies
        class Disabled < Copilot::Policies::MenuItems::GeneralPolicies::Base
          STANDALONE_BUSINESS_DESCRIPTION = "Members won’t have access to the feature"
          BUSINESS_DESCRIPTION = "All organizations won’t have access to the feature"
          REFRESH_BUSINESS_DESCRIPTION = "Organizations or users will not have access to this feature. It cannot be enabled at the organization level."
          ORGANIZATION_DESCRIPTION = "Members of this organization won’t have access to the feature"
          USER_DESCRIPTION = "You won’t have access to the feature"

          sig { override.returns(String) }
          def label
            "Disabled"
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
