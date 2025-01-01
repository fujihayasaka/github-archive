# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module MenuItems
      module PublicCodeSuggestions
        class Allowed < Copilot::Policies::MenuItems::PublicCodeSuggestions::Base
          STANDALONE_BUSINESS_DESCRIPTION = "GitHub Copilot will show suggestions matching public code."
          BUSINESS_DESCRIPTION = "GitHub Copilot will show suggestions matching public code across your organizations."
          ORGANIZATION_DESCRIPTION = "For this organization, GitHub Copilot will show suggestions matching public code."
          USER_DESCRIPTION = "GitHub Copilot will show suggestions matching public code."

          private

          sig { override.returns(T::Boolean) }
          def checked?
            allow_public_code_suggestions?
          end

          sig { override.returns(String) }
          def description
            if standalone_business?
              STANDALONE_BUSINESS_DESCRIPTION
            elsif business?
              BUSINESS_DESCRIPTION
            elsif organization?
              ORGANIZATION_DESCRIPTION
            else
              USER_DESCRIPTION
            end
          end
        end
      end
    end
  end
end
