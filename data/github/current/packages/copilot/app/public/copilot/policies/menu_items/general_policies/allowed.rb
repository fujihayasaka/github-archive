# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module MenuItems
      module GeneralPolicies
        class Allowed < Copilot::Policies::MenuItems::GeneralPolicies::Base
          STANDALONE_BUSINESS_DESCRIPTION = "GitHub Copilot will show suggestions matching public code."
          BUSINESS_DESCRIPTION = "GitHub Copilot will show suggestions matching public code across your organizations."
          ORGANIZATION_DESCRIPTION = "For this organization, GitHub Copilot will show suggestions matching public code."
          USER_DESCRIPTION = "GitHub Copilot will show suggestions matching public code."

          sig { override.returns(String) }
          def label
            "Allowed"
          end

          sig { override.returns(String) }
          def description
            if standalone_business?
              STANDALONE_BUSINESS_DESCRIPTION
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
