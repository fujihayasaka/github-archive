# typed: strict
# frozen_string_literal: true

module Orgs
  module SecurityCenter
    class SecretRiskAssessmentsController < AbstractSecurityCenterController
      include ApplicationController::VerifiedFetchDependency
      include ApplicationController::JsonDependency

      before_action :parse_json_params
      before_action :require_feature_flag
      before_action :check_secret_risk_assessments_permission

      after_action :ensure_security_overview_analytics_reconciliation, only: [:index]
      after_action :trigger_security_overview_analytics_backfill, only: [:index]

      allow_verified_fetch except: [
        :index,
      ]

      stylesheet_bundle "secret-scanning"

      sig { returns(String) }
      def self.react_bundle_name
        "secret-risk-assessment"
      end

      # TODO: Add unit tests
      sig { void }
      def index
        data = log_timing(step: "build locals") do
          {
            backfill_in_progress: ::SecurityCenter::SecurityFeatures.security_center_available?(org) ? org.trigger_security_center_reconciliation : false,
            selected_tab: :secret_risk_assessment,
          }
        end

        assessment, error = ::SecretScanning::Services::SecretRiskAssessmentsService.get_latest_assessment_for_org(org, current_user)

        raise error if error.present?

        cost = org.advanced_security_price_for_sku(sku: "ghas_secret_protection_licenses", seats: 1)
        increased_license_usage = org.secret_protection.seat_usage_increase_if_enabled_for_all_repos

        render_react_app(
          title: "Security · Assessments · #{org.display_login}",
          payload: {
            org: {
              login: org.display_login,
            },
            assessment: assessment&.serialize,
            cost: {
              increased_license_usage:,
              per_license: cost.format,
              total: (cost * increased_license_usage).format,
            },
            help_url: GitHub.help_url,
            # Temporary, for testing
            can_skip_rescan: GitHub.flipper[::SecretScanning::Features::FeatureFlagHelper::FeatureFlags::ASSESSMENT_RESCAN].enabled?(org),
            is_enterprise_or_mt: GitHub.enterprise? || GitHub.multi_tenant_enterprise?,
            show_enable_secret_protection_button: show_enable_secret_protection_cta?,
          },
          layout: "layouts/security_center/with_sidebar",
          page_data: { data: },
        )
      end

      sig { void }
      def json # rubocop:todo GitHub/UseRestfulActions
        assessment, error = ::SecretScanning::Services::SecretRiskAssessmentsService.get_latest_assessment_for_org(org, current_user)
        raise error if error.present?
        render json: assessment&.serialize
      end

      sig { void }
      def create
        # TODO: Temporary code to block someone trying to curl rescan while allowing feature flag rescans
        assessment, _ = ::SecretScanning::Services::SecretRiskAssessmentsService.get_latest_assessment_for_org(org, current_user)
        if assessment.present? && !assessment.can_request_another_assessment
          return render_404 unless GitHub.flipper[::SecretScanning::Features::FeatureFlagHelper::FeatureFlags::ASSESSMENT_RESCAN].enabled?(org)
        end

        marketing_params = request&.query_parameters.slice(:utm_source, :utm_medium, :utm_campaign, :utm_content)

        error = ::SecretScanning::Services::SecretRiskAssessmentsService.create_assessment_for_org(org, current_user, marketing_params)
        return head :internal_server_error if error.present?
        render json: nil, status: 200
      end

      sig { void }
      def results_csv # rubocop:todo GitHub/UseRestfulActions
        report, error = ::SecretScanning::Services::SecretRiskAssessmentsService.get_results_csv([org], current_user)

        raise error if error.present?

        respond_to do |format|
          format.csv { send_data report, filename: "risk_assessment_export_#{org.display_login}_#{Time.now.utc.strftime("%Y-%m-%d")}.csv", type: "text/csv" }
        end
      end

      sig { void }
      def enable_ghsp # rubocop:todo GitHub/UseRestfulActions
        include_private_repos = !!params[:includePrivateRepos]
        config_name = include_private_repos ? "Secret Protection enabled" : "Secret Protection enabled for public repositories"
        config_description = "Settings for Secret Protection, enabled from the organization assessment."
        SecretScanningBulkEnablementJob.perform_later(
          org: org,
          actor: current_user,
          config_name: config_name,
          config_description: config_description,
          include_private_repos: include_private_repos,
          enable_on_unattached_repos_with_conflict: true
        )
        render json: nil, status: :ok
      end

      sig { void }
      def has_config_conflict # rubocop:todo GitHub/UseRestfulActions
        has_repo_conflict = ::SecretScanning::BulkEnablementService.entity_has_private_repo_conflict(org)
        render json: { has_repo_conflict: has_repo_conflict }, status: :ok
      end

      private

      sig { void }
      def require_feature_flag
        render_404 unless ::SecretScanning::Features::Org::TokenScanning.new(org).secret_risk_assessment_available?
      end

      sig { void }
      def check_secret_risk_assessments_permission
        return render_404 unless this_organization
        return render_404 unless current_user
        render_404 unless ::SecretScanning::AccessControl::SecretRiskAssessments.new(org).has_access_to_secret_risk_assessments?(current_user)
      end

      sig { returns(Organization) }
      def org
        this_organization
      end

      sig { returns(T::Boolean) }
      def show_enable_secret_protection_cta?
        return true unless GitHub.enterprise?

        # Do not show if secret scanning is not enabled in ghe-config
        return false unless GitHub.configuration_secret_scanning_enabled?

        # Check if GHAS is purchased if org is bundled
        return org.advanced_security_purchased? if org.advanced_security_products_bundled?

        # Check if unbundled Secret Protection is purchased
        org.secret_protection_purchased?
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
          :json,
          :results_csv,
          :has_config_conflict,
        ],
      )
    end
  end
end
