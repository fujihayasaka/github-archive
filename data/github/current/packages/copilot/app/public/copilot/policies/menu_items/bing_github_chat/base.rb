# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module MenuItems
      module BingGitHubChat
        class Base < Copilot::Policies::MenuItems::Base
          abstract!

          private

          delegate :bing_github_chat_enabled?, :bing_github_chat_disabled?, :bing_github_chat_no_policy?, to: :copilot_configurable

          sig { override.returns(String) }
          def name
            "bing_github_chat"
          end
        end
      end
    end
  end
end
