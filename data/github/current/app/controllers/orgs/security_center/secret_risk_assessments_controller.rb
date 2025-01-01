# typed: strict
# frozen_string_literal: true

module Orgs
  module SecurityCenter
    class SecretRiskAssessmentsController < AbstractSecurityCenterController
      include ApplicationController::VerifiedFetchDependency
      include ApplicationController::JsonDependency
      include ::SecretScanning::Features::FeatureFlagHelper
      include InProductTargeting::ScanSecretLeaksConcern

      # Reusable name & description for Secret Protection configuration used by enablement jobs
      DEFAULT_CONFIG_NAME = T.let("Secret Protection enabled", String)
      DEFAULT_CONFIG_DESCRIPTION = T.let("Settings for Secret Protection, enabled from the organization assessment.", String)

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
        assessment, error = ::SecretScanning::Services::SecretRiskAssessmentsService.get_latest_assessment_for_org(org, current_user)
        assessment_list, _list_error = ::SecretScanning::Services::SecretRiskAssessmentsService.list_assessments(org)

        add_client_feature_flag([
          ::SecretScanning::Features::FeatureFlagHelper::FeatureFlags::SECRET_PROTECTION_PRICING_CALCULATOR,
          ::SecretScanning::Features::FeatureFlagHelper::FeatureFlags::SECRET_PROTECTION_PRICING_CALCULATOR_METERED_ORGS
        ], entity: org)

        render_assessment_view(
          assessment:,
          assessment_list:,
          assessment_number: nil,
          show_error_banner: error.present?,
        )
      end

      sig { void }
      def show
        assessment_number = params[:id].to_i
        # If assessment_number is not provided or invalid, fetch the latest assessment
        if assessment_number <= 0
          assessment, error = ::SecretScanning::Services::SecretRiskAssessmentsService.get_latest_assessment_for_org(org, current_user)
        else
          assessment, error = ::SecretScanning::Services::SecretRiskAssessmentsService.get_assessment(org, assessment_number)
        end
        assessment_list, _list_error = ::SecretScanning::Services::SecretRiskAssessmentsService.list_assessments(org)

        return render_404 if assessment.nil?

        add_client_feature_flag([
          ::SecretScanning::Features::FeatureFlagHelper::FeatureFlags::SECRET_PROTECTION_PRICING_CALCULATOR,
          ::SecretScanning::Features::FeatureFlagHelper::FeatureFlags::SECRET_PROTECTION_PRICING_CALCULATOR_METERED_ORGS
        ], entity: org)

        render_assessment_view(
          assessment:,
          assessment_list:,
          assessment_number:,
          show_error_banner: error.present?,
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
          return render_404 unless FeatureFlag.vexi.enabled?(::SecretScanning::Features::FeatureFlagHelper::FeatureFlags::ASSESSMENT_RESCAN, org, default: false)
        end

        marketing_params = request&.query_parameters.slice(:utm_source, :utm_medium, :utm_campaign, :utm_content)

        error = ::SecretScanning::Services::SecretRiskAssessmentsService.create_assessment_for_org(org, current_user, marketing_params)
        return head :internal_server_error if error.present?
        render json: nil, status: 200
      end

      sig { void }
      def results_csv # rubocop:todo GitHub/UseRestfulActions
        if feature_flag_enabled_in_hierarchy?(org, ::SecretScanning::Features::FeatureFlagHelper::FeatureFlags::DISPLAY_PREVIOUS_ASSESSMENTS)
          assessment_number = params[:id]&.to_i
        else
          assessment_number = nil
        end

        report, error = ::SecretScanning::Services::SecretRiskAssessmentsService.get_results_csv([org], current_user, assessment_number)
        raise error if error.present?

        respond_to do |format|
          format.csv { send_data report, filename: "risk_assessment_export_#{org.display_login}_#{assessment_number.nil? ? Time.now.utc.strftime("%Y-%m-%d") : assessment_number}.csv", type: "text/csv" }
        end
      end

      sig { void }
      def enable_ghsp # rubocop:todo GitHub/UseRestfulActions
        include_private_repos = !!params[:includePrivateRepos]
        config_name = include_private_repos ? DEFAULT_CONFIG_NAME : "Secret Protection enabled for public repositories"

        SecretScanningBulkEnablementJob.perform_later(
          org: org,
          actor: current_user,
          config_name: config_name,
          config_description: DEFAULT_CONFIG_DESCRIPTION,
          include_private_repos: include_private_repos,
          enable_on_unattached_repos_with_conflict: true
        )
        render json: nil, status: :ok
      end

      sig { void }
      def enable_ghsp_on_selected_repos # rubocop:todo GitHub/UseRestfulActions
        unless feature_flag_enabled_in_hierarchy?(org, ::SecretScanning::Features::FeatureFlagHelper::FeatureFlags::SECRET_PROTECTION_PRICING_CALCULATOR)
          return render json: { error: "Feature not enabled" }, status: :unprocessable_entity
        end


        requested_repo_ids = Array(params[:repoIds] || []).map(&:to_i)
        repo_ids = org.repositories.where(id: requested_repo_ids).distinct.pluck(:id)

        if repo_ids.any?
          SecretScanningSelectiveEnablementJob.perform_later(
            org: org,
            actor: current_user,
            config_name: DEFAULT_CONFIG_NAME,
            config_description: DEFAULT_CONFIG_DESCRIPTION,
            repo_ids: repo_ids
          )
        end

        render json: { repo_count: repo_ids.length }, status: :ok
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
      memoize def secret_scanning_completely_enabled?
        return false unless ::SecretScanning::Features::Org::TokenScanning.new(org).assessments_check_all_repos_enabled?

        enabled, error = ::SecretScanning::Services::EnablementStatusService.secret_scanning_enabled(org)

        return false if error
        enabled
      end

      sig { returns(T::Boolean) }
      def show_enable_secret_protection_button?
        return true unless GitHub.enterprise?

        # Do not show if secret scanning is not enabled in ghe-config
        return false unless GitHub.configuration_secret_scanning_enabled?

        # Check if GHAS is purchased if org is bundled
        return org.advanced_security_purchased? if org.advanced_security_products_bundled?

        # Check if unbundled Secret Protection is purchased
        org.secret_protection_purchased?
      end

      sig { returns(T::Boolean) }
      def show_enable_secret_protection_banner?
        return true unless ::SecretScanning::Features::Org::TokenScanning.new(org).assessments_check_all_repos_enabled?

        security_center_available = ::SecurityCenter::SecurityFeatures.security_center_available?(org)
        GitHub.dogstats.increment(
          "secret_scanning.risk_assessment.all_repos_enabled.security_center_available",
          tags: [
          "plan:#{org.plan.business? ? "team" : "other"}",
          "security_center_available:#{security_center_available}",
          ],
        )

        return true unless security_center_available

        GitHub.logger.info(
          "security center available, checking secret scanning enablement status for org",
          {
            "code.namespace" => self.class.name,
            "code.function" => __method__,
            "org.id" => org.id,
            "plan" => (org.plan.business? ? "team" : "other"),
            "security_center_available" => security_center_available,
          },
        )

        !secret_scanning_completely_enabled?
      end

      sig do
        params(
          assessment: T.nilable(::SecretScanning::Models::RiskAssessment::Assessment),
          assessment_list: T.untyped,
          assessment_number: T.nilable(Integer),
          show_error_banner: T::Boolean,
        ).void
      end
      def render_assessment_view(assessment:, assessment_list:, assessment_number:, show_error_banner: false)
        data = log_timing(step: "build locals") do
          {
            backfill_in_progress: ::SecurityCenter::SecurityFeatures.security_center_available?(org) ? org.trigger_security_center_reconciliation : false,
            selected_tab: :secret_risk_assessment,
          }
        end
        sku = org.advanced_security_products_bundled? ? "ghas_licenses" : "ghas_secret_protection_licenses"
        cost = org.advanced_security_price_for_sku(sku: sku, seats: 1)
        increased_license_usage = org.secret_protection.seat_usage_increase_if_enabled_for_all_repos

        payload = {
          org: {
            login: org.display_login,
            is_ghas_bundled: org.advanced_security_products_bundled?,
            is_ghas_metered: org.advanced_security_products_metered?,
          },
          assessment: assessment&.serialize,
          assessmentList: assessment_list,
          cost: {
            increased_license_usage:,
            per_license: cost.format,
            total: (cost * increased_license_usage).format,
          },
          help_url: GitHub.help_url,
          can_skip_rescan: FeatureFlag.vexi.enabled?(::SecretScanning::Features::FeatureFlagHelper::FeatureFlags::ASSESSMENT_RESCAN, org, default: false),
          # Currently manually setting to control but this can be set to an assisgnment function in the future
          # If we decide to A|B test this functionality again which we very well might
          # See https://github.com/github/github/pull/395798 for prior-art
          hawaii_exp_variant: 0,
          is_enterprise_or_mt: GitHub.enterprise? || GitHub.multi_tenant_enterprise?,
          show_enable_secret_protection_button: show_enable_secret_protection_button?,
          show_enable_secret_protection_banner: show_enable_secret_protection_banner?,
          display_previous_assessments: feature_flag_enabled_in_hierarchy?(org, ::SecretScanning::Features::FeatureFlagHelper::FeatureFlags::DISPLAY_PREVIOUS_ASSESSMENTS),
          show_roi_calculator: feature_flag_enabled_in_hierarchy?(org, ::SecretScanning::Features::FeatureFlagHelper::FeatureFlags::SECURITY_ASSESSMENTS_ENABLE_ROI_CALCULATOR),
          show_error_banner:,
        }

        # Add assessment number only for show action
        payload[:number] = assessment_number.to_i if assessment_number.present?

        render_react_app(
          title: "Security · Assessments · #{org.display_login}",
          payload: payload,
          layout: "layouts/security_center/with_sidebar",
          page_data: { data: },
        )
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
          :show,
          :json,
          :results_csv,
          :has_config_conflict,
        ],
      )
    end
  end
end
