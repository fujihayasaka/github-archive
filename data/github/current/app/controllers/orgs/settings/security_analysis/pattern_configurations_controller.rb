# typed: strict
# frozen_string_literal: true

require "react_payload"

module Orgs
  module Settings
    module SecurityAnalysis
      class PatternConfigurationsController < Orgs::Controller
        include ApplicationController::VerifiedFetchDependency
        include ApplicationController::JsonDependency

        before_action :require_feature_flag
        before_action :parse_json_params
        before_action :ensure_current_organization
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

          render_react_html(
            title: "Settings · Pattern configurations · #{org.display_login}",
            payload: IndexPayload.new({
              org: {
                login: org.display_login,
              },
              pattern_config: pattern_config.serialize,
              # TODO: Hiding the column for now until biz level is implemented
              has_parent: false,
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
          number = params[:number].to_i
          row_version = params[:row_version]
          pattern_settings = Array(params[:pattern_settings]).map do |setting|
            result, error = ::SecretScanning::Models::PatternConfigurations::PatternOverrideUpdate.from_params(setting)
            return render json: { error: }, status: 422 if error || result.nil?
            result
          end
          return render json: { error: "pattern_settings is required" }, status: 422 if pattern_settings.empty?

          row_version, err = ::SecretScanning::Services::PatternConfigsService.upsert_pattern_config(
            owner: org,
            user: current_user,
            number:,
            row_version:,
            pattern_settings:,
          )
          raise err if err.present?
          render json: { row_version: }, status: 200
        end

        private

        sig { void }
        def require_feature_flag
          render_404 unless ::SecretScanning::Features::FeatureFlagHelper.feature_flag_enabled_in_hierarchy?(
            org,
            ::SecretScanning::Features::FeatureFlagHelper::FeatureFlags::PATTERN_CONFIG,
          )
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
