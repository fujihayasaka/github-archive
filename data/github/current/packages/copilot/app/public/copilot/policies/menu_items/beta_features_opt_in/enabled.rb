# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module MenuItems
      module BetaFeaturesOptIn
        class Enabled < Copilot::Policies::MenuItems::BetaFeaturesOptIn::Base
          BUSINESS_DESCRIPTION = "All organizations will have access to the feature"
          ORGANIZATION_DESCRIPTION = "Members with a Copilot license will have access to the feature"

          private

          sig { override.returns(T::Boolean) }
          def checked?
            beta_features_github_chat_enabled?
          end

          sig { override.returns(String) }
          def description
            business? ? BUSINESS_DESCRIPTION : ORGANIZATION_DESCRIPTION
          end
        end
      end
    end
  end
end
