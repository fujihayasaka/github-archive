# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module MenuItems
      module BingGitHubChat
        class Disabled < Copilot::Policies::MenuItems::BingGitHubChat::Base
          BUSINESS_DESCRIPTION = "Organizations won’t have access to the feature"
          ORGANIZATION_DESCRIPTION = "Members of this organization won’t have access to the feature"
          USER_DESCRIPTION = "GitHub Copilot won't answer questions about new trends and give improved answers"

          private

          sig { override.returns(T::Boolean) }
          def checked?
            bing_github_chat_disabled?
          end

          sig { override.returns(String) }
          def description
            if business?
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
