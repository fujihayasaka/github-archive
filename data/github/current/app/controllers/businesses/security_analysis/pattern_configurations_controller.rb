# typed: strict
# frozen_string_literal: true

require "react_payload"

module Businesses
  module SecurityAnalysis
    class PatternConfigurationsController < Businesses::BusinessController
      include ApplicationController::VerifiedFetchDependency
      include ApplicationController::JsonDependency

      before_action :parse_json_params
      before_action :business_full_plan_required
      before_action :secret_scanning_required
      before_action :modify_security_settings_permission_required

      allow_verified_fetch except: [
        :index,
      ]

      sig { returns(String) }
      def self.react_bundle_name
        "push-protection-pattern-configurations"
      end

      sig { void }
      def index
        pattern_config, err = ::SecretScanning::Services::PatternConfigsService.get_pattern_config_by_owner(business, current_user)
        raise err if err.present?
        return render_404 if pattern_config.nil?

        render_react_html(
          title: "GitHub Advanced Security",
          payload: IndexPayload.new({
            pattern_config: pattern_config.serialize_ui,
            has_parent: false,
            security_settings_path: settings_security_analysis_enterprise_path(business),
          }),
          page_data: {
            selected_link: :business_security_analysis,
            sidebar: :settings
          },
          layout: "react_business",
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
          owner: business,
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

      sig { returns(Business) }
      def business
        this_business
      end

      # TODO: Move to business controller
      sig { void }
      def business_required
        render_404 unless this_business
      end

      # TODO: Move to new base controller
      sig { void }
      def secret_scanning_required
        render_404 unless ::SecretScanning::Features::Business::TokenScanning.new(business).feature_available?
      end

      # TODO: Move to new base controller
      sig { void }
      def modify_security_settings_permission_required
        business_authz = SecurityProduct::Permissions::BusinessAuthz.new(business, actor: current_user)
        render_404 unless business_authz.can_modify_code_security_settings?
      end

      class IndexPayload < ReactPayload::Base
        sig { override.returns(String) }
        def route_id
          "businessPatternConfigsPageRoute"
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
