# typed: strict
# frozen_string_literal: true

require "react_payload"

module Orgs
  module Settings
    module SecurityAnalysis
      class PatternConfigurationsController < Orgs::Controller
        include ApplicationController::VerifiedFetchDependency
        include ApplicationController::JsonDependency

        before_action :parse_json_params
        before_action :ensure_current_organization
        before_action :require_feature
        before_action :manage_security_products_permission_required

        allow_verified_fetch except: [
          :index,
        ]

        sig { returns(String) }
        def self.react_bundle_name
          "push-protection-pattern-configurations"
        end

        sig { void }
        def index
          pattern_config, err = ::SecretScanning::Services::PatternConfigsService.get_pattern_config_by_owner(org, current_user)
          raise err if err.present?
          return render_404 if pattern_config.nil?

          respond_with_react(
            title: "Settings · Pattern configurations · #{org.display_login}",
            payload: IndexPayload.new({
              pattern_config: pattern_config.serialize_ui,
              has_parent: org.business.present?,
              security_settings_path: settings_org_security_analysis_path(org),
            }),
            page_data: {
              selected_link: :security_analysis,
            },
            layout: "organization_settings",
          )
        end

        sig { void }
        def update
          row_version = params[:row_version]
          provider_pattern_settings = Array(params[:provider_pattern_settings]).map do |setting|
            result, error = ::SecretScanning::Models::PatternConfigurations::PatternOverrideUpdate.from_params(setting)
            return render json: { error: }, status: 422 if error || result.nil?
            result
          end
          custom_pattern_settings = Array(params[:custom_pattern_settings]).map do |setting|
            result, error = ::SecretScanning::Models::PatternConfigurations::CustomPatternOverrideUpdate.from_params_ui(setting)
            return render json: { error: }, status: 422 if error || result.nil?
            result
          end
          return render json: { error: "pattern_settings is required" }, status: 422 if provider_pattern_settings.empty? && custom_pattern_settings.empty?

          row_version, number, err = ::SecretScanning::Services::PatternConfigsService.upsert_pattern_config(
            owner: org,
            user: current_user,
            row_version:,
            provider_pattern_settings:,
            custom_pattern_settings:,
          )
          return render json: { error: "row_version mismatch" }, status: 409 if err.is_a?(::SecretScanning::Errors::RowVersionMismatch)
          raise err if err.present?
          render json: { row_version:, number: }, status: 200
        end

        private

        sig { void }
        def require_feature
          render_404 unless ::SecretScanning::Features::Org::PushProtection.new(org).pattern_configs_available?
        end

        sig { returns(Organization) }
        def org
          this_organization
        end

        class IndexPayload < ReactPayload::Base
          sig { override.returns(String) }
          def route_id
            "patternConfigsPageRoute"
          end

          sig { params(payload: T::Hash[String, T.untyped]).void }
          def initialize(payload)
            @payload = payload
          end

          sig { override.returns(T::Hash[String, T.untyped]) }
          def payload
            @payload
          end
        end

        depends_on_clusters(
          ApplicationRecord::Mysql1,
          ApplicationRecord::Mysql2,
          ApplicationRecord::Configurations,
          ApplicationRecord::Iam,
          ApplicationRecord::IamAbilities,
          ApplicationRecord::Repositories,
          ApplicationRecord::Notify,
          ApplicationRecord::NotificationsEntries,
          ApplicationRecord::Collab,
          ApplicationRecord::SecurityOverviewAnalytics,
          ApplicationRecord::Billing,
          ApplicationRecord::Copilot,
          only: [
            :index,
          ],
        )
      end
    end
  end
end
