# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module MenuItems
      module BetaFeaturesOptIn
        class Base < Copilot::Policies::MenuItems::Base
          abstract!

          private

          delegate :beta_features_github_chat_enabled?, :beta_features_github_chat_disabled?, :beta_features_github_chat_no_policy?, to: :copilot_configurable

          sig { override.returns(String) }
          def name
            "beta_features_github_chat"
          end
        end
      end
    end
  end
end
