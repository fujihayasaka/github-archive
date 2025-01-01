# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module MenuItems
      module BetaFeaturesOptIn
        class Disabled < Copilot::Policies::MenuItems::BetaFeaturesOptIn::Base
          BUSINESS_DESCRIPTION = "Organizations won’t have access to the feature"
          ORGANIZATION_DESCRIPTION = "Members of this organization won’t have access to the feature"

          private

          sig { override.returns(T::Boolean) }
          def checked?
            beta_features_github_chat_disabled?
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
