# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module MenuItems
      module BingGitHubChat
        class Enabled < Copilot::Policies::MenuItems::BingGitHubChat::Base
          BUSINESS_DESCRIPTION = "All organizations will have access to the feature"
          ORGANIZATION_DESCRIPTION = "Members with a Copilot license will have access to the feature"
          USER_DESCRIPTION = "GitHub Copilot will answer questions about new trends and give improved answers"

          private

          sig { override.returns(T::Boolean) }
          def checked?
            bing_github_chat_enabled?
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
