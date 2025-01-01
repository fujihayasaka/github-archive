# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module MenuItems
      module AutomaticCodeReview
        class Disabled < Copilot::Policies::MenuItems::AutomaticCodeReview::Base
          STANDALONE_BUSINESS_DESCRIPTION = "Members won’t have access to the feature"
          BUSINESS_DESCRIPTION = "All organizations won’t have access to the feature"
          ORGANIZATION_DESCRIPTION = "Members of this organization won’t have access to the feature"
          USER_DESCRIPTION = "Copilot won't enforce automated reviews."

          private

          sig { override.returns(String) }
          def text
            "No policy"
          end

          sig { override.returns(T::Boolean) }
          def checked?
            automatic_code_review_disabled?
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
