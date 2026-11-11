# typed: strict
# frozen_string_literal: true

module Stafftools
  module Businesses
    class DefaultModelsController < Stafftools::Businesses::BusinessBaseController
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
        ApplicationRecord::Ballast, only: [:index]

      before_action :dotcom_required

      sig { returns(String) }
      def self.react_bundle_name
        "default-model-settings"
      end

      sig { void }
      def index
        add_client_feature_flag([:use_setting_rules_copilot_models], entity: this_business)
        respond_with_react(
          payload: OverviewRoutePayload.new,
          title: "GitHub Copilot Models",
          layout: "layouts/stafftools/business",
          app_payload_generator: -> { app_payload(is_stafftools: true) },
          page_data: {
            selected_link: :businesses_ai_controls_copilot,
            sidebar: :ai_controls,
          },
        )
      end

      sig { void }
      def organizations_data # rubocop:disable GitHub/UseRestfulActions
        render json: organizations
      end

      sig { void }
      def models_data # rubocop:disable GitHub/UseRestfulActions
        render json: models
      end

      sig { void }
      def settings_data # rubocop:disable GitHub/UseRestfulActions
        render json: settings
      end

      class OverviewRoutePayload < ::Businesses::AiControls::DefaultModelsController::OverviewRoutePayload
        sig { override.returns(String) }
        def route_id
          "stafftoolsOverviewRoute"
        end
      end
    end
  end
end
