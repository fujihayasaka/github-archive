# typed: strict
# frozen_string_literal: true

module Stafftools
  module Businesses
    class DefaultModelRulesController < Stafftools::Businesses::BusinessBaseController
      include ApplicationController::JsonDependency
      include ApplicationController::VerifiedFetchDependency
      include GitHub::Memoizer
      include ::Businesses::AiControls::Concerns::DefaultModels

      depends_on_clusters ApplicationRecord::Mysql1,
        ApplicationRecord::Configurations,
        ApplicationRecord::IamAbilities,
        ApplicationRecord::Collab,
        ApplicationRecord::Mysql5,
        ApplicationRecord::Mysql2,
        ApplicationRecord::NotificationsEntries,
        ApplicationRecord::Repositories,
        ApplicationRecord::Copilot,
        ApplicationRecord::Billing,
        ApplicationRecord::Ballast

      before_action :dotcom_required

      sig { returns(String) }
      def self.react_bundle_name
        "default-model-settings"
      end

      sig { void }
      def index
        respond_with_react(
          payload: RuleRoutePayload.new,
          title: "GitHub Copilot Model Rule",
          layout: "layouts/stafftools/business",
          app_payload_generator: -> { app_payload(is_stafftools: true) },
          page_data: {
            selected_link: :businesses_ai_controls_copilot,
            sidebar: :ai_controls,
          },
        )
      end

      class RuleRoutePayload < ::Businesses::AiControls::DefaultModelRulesController::RuleRoutePayload
        sig { override.returns(String) }
        def route_id
          "stafftoolsRuleRoute"
        end
      end
    end
  end
end
