# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module MenuItems
      module AutomaticCodeReview
        class Enabled < Copilot::Policies::MenuItems::AutomaticCodeReview::Base
          STANDALONE_BUSINESS_DESCRIPTION = "Members will have access to the feature"
          BUSINESS_DESCRIPTION = "All organizations will have access to the feature"
          ORGANIZATION_DESCRIPTION = "Members with a Copilot license will have access to the feature"
          USER_DESCRIPTION = "Copilot automatically reviews pull requests you authored from your repositories."

          private

          sig { override.returns(T::Boolean) }
          def checked?
            automatic_code_review_enabled?
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
