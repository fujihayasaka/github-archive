# typed: strict
# frozen_string_literal: true

module Orgs
  module SecurityCenter
    class RiskAssessmentsController < AbstractSecurityCenterController
      include ApplicationController::VerifiedFetchDependency
      include ApplicationController::JsonDependency
      include ::SecretScanning::Features::FeatureFlagHelper
      include InProductTargeting::ScanSecretLeaksConcern

      # Reusable name & description for Secret Protection configuration used by enablement jobs
      DEFAULT_CONFIG_NAME = T.let("Secret Protection enabled", String)
      DEFAULT_CONFIG_DESCRIPTION = T.let("Settings for Secret Protection, enabled from the organization assessment.", String)
      # Reusable name & description for Code Scanning configuration used by enablement jobs
      CS_DEFAULT_CONFIG_NAME = T.let("Code Scanning enabled", String)
      CS_DEFAULT_CONFIG_DESCRIPTION = T.let("Settings for Code Scanning, enabled from the organization assessment.", String)
      # 90-day cooldown period for CSRA (same as SRA) - sourced from model
      CSRA_COOLDOWN_DAYS = ::SecurityProductsEnablement::CodeScanningAssessment::COOLDOWN_DAYS

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

      sig { void }
      def index
        return render_404 if params[:feature] == "code-security" && !csra_feature_flag_enabled?

        if csra_feature_flag_enabled?
          render_combined_assessment_index
        else
          render_secret_protection_index
        end
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
      def csra_json # rubocop:todo GitHub/UseRestfulActions
        return render_404 unless csra_feature_flag_enabled?

        results = ::SecurityProductsEnablement::CodeScanningAssessment.latest_results_for_org(org)
        render json: results&.as_json, status: :ok
      end

      # Returns the additional committer count for a single repository.
      sig { void }
      def committer_count # rubocop:todo GitHub/UseRestfulActions
        return render_404 unless FeatureFlag.vexi.enabled?(:code_security_risk_assessment, org, default: false)

        repo = org.repositories.find_by(id: params[:repository_id])
        return render_404 unless repo

        sku = org.advanced_security_products_bundled? ? GitHub::Turboghas::SKU::Bundled : GitHub::Turboghas::SKU::CodeSecurity
        licensing_service = ::SecurityProductsEnablement::QuickSetupService::LicensingService.new(organization: org)
        committer_data = licensing_service.fetch_committer_data_for_feature(
          [{ id: repo.id, visibility: repo.visibility, archived: repo.archived? }],
          sku,
        )
        count = committer_data.fetch(repo.id, []).size

        render json: { committer_count: count }
      end

      sig { void }
      def create
        if csra_feature_flag_enabled?
          create_assessments
        else
          create_sra_only
        end
      end

      sig { void }
      def results_csv # rubocop:todo GitHub/UseRestfulActions
        assessment_number = params[:id]&.to_i

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

        render json: { show_security_dashboard_button: show_security_dashboard_button?(has_private_repos: include_private_repos) }, status: :ok
      end

      sig { void }
      def enable_ghsp_on_selected_repos # rubocop:todo GitHub/UseRestfulActions
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

        render json: { repo_count: repo_ids.length, show_security_dashboard_button: show_security_dashboard_button?(repo_ids: repo_ids) }, status: :ok
      end

      sig { void }
      def has_config_conflict # rubocop:todo GitHub/UseRestfulActions
        has_repo_conflict = ::SecretScanning::BulkEnablementService.entity_has_private_repo_conflict(org)
        render json: { has_repo_conflict: has_repo_conflict }, status: :ok
      end

      sig { void }
      def enable_code_scanning # rubocop:todo GitHub/UseRestfulActions
        return render_404 unless csra_feature_flag_enabled?

        CodeScanningBulkEnablementJob.perform_later(
          org: org,
          actor: current_user,
          config_name: CS_DEFAULT_CONFIG_NAME,
          config_description: CS_DEFAULT_CONFIG_DESCRIPTION,
          enable_on_unattached_repos_with_conflict: true
        )

        has_private_repos = org.repositories.where(public: false).exists?
        render json: { show_security_dashboard_button: show_security_dashboard_button?(has_private_repos: has_private_repos) }, status: :ok
      end

      sig { void }
      def enable_code_scanning_on_selected_repos # rubocop:todo GitHub/UseRestfulActions
        return render_404 unless csra_feature_flag_enabled?

        requested_repo_ids = Array(params[:repoIds] || []).map(&:to_i)
        repo_ids = org.repositories.where(id: requested_repo_ids).distinct.pluck(:id)

        if repo_ids.any?
          CodeScanningSelectiveEnablementJob.perform_later(
            org: org,
            actor: current_user,
            config_name: CS_DEFAULT_CONFIG_NAME,
            config_description: CS_DEFAULT_CONFIG_DESCRIPTION,
            repo_ids: repo_ids
          )
        end

        render json: { repo_count: repo_ids.length, show_security_dashboard_button: show_security_dashboard_button?(repo_ids: repo_ids) }, status: :ok
      end

      sig { void }
      def has_code_scanning_config_conflict # rubocop:todo GitHub/UseRestfulActions
        return render_404 unless csra_feature_flag_enabled?

        has_repo_conflict = ::CodeScanning::BulkEnablementService.entity_has_private_repo_conflict(org)
        render json: { has_repo_conflict: has_repo_conflict }, status: :ok
      end

      sig { void }
      def eligibility # rubocop:todo GitHub/UseRestfulActions
        render json: build_eligibility_payload
      end

      private

      sig { returns(T::Boolean) }
      memoize def csra_feature_flag_enabled?
        FeatureFlag.vexi.enabled?(:code_security_risk_assessment, org, default: false)
      end

      sig { void }
      def render_combined_assessment_index
        sra_assessment, sra_error = latest_sra_assessment_with_error
        csra_assessment = ::SecurityProductsEnablement::CodeScanningAssessment.where(owner_id: org.id).order(number: :desc).first
        has_sra = sra_assessment.present?
        has_csra = csra_assessment.present?

        if params[:feature] == "secret-protection"
          render_secret_protection_feature(has_sra:, has_csra:, sra_assessment:, sra_error:)
        else
          render_code_security_feature(has_sra:, has_csra:, sra_assessment:, sra_error:, csra_assessment:)
        end
      end

      sig do
        params(
          has_sra: T::Boolean,
          has_csra: T::Boolean,
          sra_assessment: T.nilable(::SecretScanning::Models::RiskAssessment::Assessment),
          sra_error: T.untyped,
        ).void
      end
      def render_secret_protection_feature(has_sra:, has_csra:, sra_assessment:, sra_error:)
        # Transitional path during CSRA rollout: show SRA landing when only CSRA exists
        if has_csra && !has_sra
          render_landing_page(
            feature: "secret-protection",
            view_state: "sra_landing",
          )
        else
          assessment_list, _list_error = ::SecretScanning::Services::SecretRiskAssessmentsService.list_assessments(org)

          render_assessment_view(
            assessment: sra_assessment,
            assessment_list:,
            assessment_number: nil,
            show_error_banner: sra_error.present?,
          )
        end
      end

      sig do
        params(
          has_sra: T::Boolean,
          has_csra: T::Boolean,
          sra_assessment: T.nilable(::SecretScanning::Models::RiskAssessment::Assessment),
          sra_error: T.untyped,
          csra_assessment: T.nilable(::SecurityProductsEnablement::CodeScanningAssessment),
        ).void
      end
      def render_code_security_feature(has_sra:, has_csra:, sra_assessment:, sra_error:, csra_assessment:)
        view_state = if !has_sra && !has_csra
          "shared_landing"
        elsif has_sra && !has_csra
          "csra_landing"
        else
          "csra_results"
        end

        sra_assessment_list, _list_error = has_sra ? ::SecretScanning::Services::SecretRiskAssessmentsService.list_assessments(org) : [nil, nil]
        render_landing_page(
          feature: "code-security",
          view_state:,
          assessment_number: csra_assessment&.number,
          sra_assessment: sra_assessment,
          sra_assessment_list: sra_assessment_list,
          sra_error: sra_error.present?,
          csra_assessment: csra_assessment,
        )
      end

      sig { void }
      def create_assessments
        boolean_type = ActiveModel::Type::Boolean.new

        run_sra = boolean_type.cast(params[:run_sra])
        run_csra = boolean_type.cast(params[:run_csra])

        unless run_sra || run_csra
          return render json: { error: "At least one assessment type must be selected" }, status: :unprocessable_entity
        end

        sra_result = run_sra ? build_sra_result : { created: false, error: nil }
        csra_result = run_csra ? build_csra_result : { created: false, error: nil }

        log_assessment_error("SRA", sra_result[:error])
        log_assessment_error("CSRA", csra_result[:error])

        # Always return 200 with per-product results in the body.
        # Individual product errors (cooldown, validation, service failures)
        # are reported in each product's error field rather than via HTTP status,
        # since the request itself was valid and results are independent.
        render json: { sra: sra_result, csra: csra_result }, status: :ok
      end

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def build_sra_result
        unless sra_eligible?
          return { created: false, error: "Assessment not eligible - cooldown period active" }
        end

        marketing_params = request.query_parameters.slice(:utm_source, :utm_medium, :utm_campaign, :utm_content)
        sra_error = ::SecretScanning::Services::SecretRiskAssessmentsService.create_assessment_for_org(org, current_user, marketing_params)
        { created: sra_error.nil?, error: sra_error&.message }
      end

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def build_csra_result
        unless csra_eligible?
          return { created: false, error: "Assessment not eligible - cooldown period active" }
        end

        normalized_repository_ids = Array(params[:repository_ids]).map { |id| ActiveModel::Type::Integer.new.cast(id) }.compact
        marketing_params = request.query_parameters.slice(:utm_source, :utm_medium, :utm_campaign, :utm_content)
        csra_error = ::SecurityProductsEnablement::CodeScanningAssessment.create_assessment_for_org(
          org: org,
          actor: current_user,
          repository_ids: normalized_repository_ids,
          marketing_info: marketing_params,
        )
        { created: csra_error.nil?, error: csra_error }
      end

      sig { void }
      def create_sra_only
        return render_404 unless sra_eligible?

        marketing_params = request.query_parameters.slice(:utm_source, :utm_medium, :utm_campaign, :utm_content)
        sra_error = ::SecretScanning::Services::SecretRiskAssessmentsService.create_assessment_for_org(org, current_user, marketing_params)
        return head :internal_server_error if sra_error.present?

        render json: nil, status: 200
      end

      sig { params(type: String, error: T.untyped).void }
      def log_assessment_error(type, error)
        return unless error.present?

        GitHub.logger.error("Failed to create #{type} during assessment creation", {
          "code.namespace": self.class.name,
          "gh.org.id": org.id,
          "gh.user.id": current_user.id,
          "error.message": error,
        })
      end

      sig do
        params(
          assessment: T.nilable(::SecretScanning::Models::RiskAssessment::Assessment),
          assessment_list: T.untyped,
          show_error_banner: T::Boolean,
        ).returns(T::Hash[Symbol, T.untyped])
      end
      def build_sra_payload(assessment:, assessment_list:, show_error_banner: false)
        sku = org.advanced_security_products_bundled? ? "ghas_licenses" : "ghas_secret_protection_licenses"
        license = org.advanced_security_products_bundled? ? org.advanced_security_license : org.secret_protection

        {
          **common_payload(sku:, license:, show_error_banner:),
          assessment: assessment&.serialize,
          assessmentList: assessment_list,
          can_skip_rescan: FeatureFlag.vexi.enabled?(::SecretScanning::Features::FeatureFlagHelper::FeatureFlags::ASSESSMENT_RESCAN, org, default: false),
          # Currently manually setting to control but this can be set to an assignment function in the future
          # If we decide to A|B test this functionality again which we very well might
          # See https://github.com/github/github/pull/395798 for prior-art
          hawaii_exp_variant: 0,
          show_enable_secret_protection_button: show_enable_secret_protection_button?,
          show_enable_secret_protection_banner: show_enable_secret_protection_banner?,
        }
      end

      sig do
        params(
          csra_assessment: ::SecurityProductsEnablement::CodeScanningAssessment,
        ).returns(T::Hash[Symbol, T.untyped])
      end
      def build_csra_payload(csra_assessment:)
        sku = org.advanced_security_products_bundled? ? "ghas_licenses" : "ghas_code_security_licenses"
        cost = org.advanced_security_price_for_sku(sku: sku, seats: 1)
        license = org.advanced_security_products_bundled? ? org.advanced_security_license : org.code_security
        increased_license_usage = license.seat_usage_increase_if_enabled_for_all_repos

        results_payload = csra_assessment.build_results_payload(
          can_request_another_assessment: csra_assessment.can_request_another_assessment?,
          next_request_available_at: csra_assessment.cooldown_ends_at,
        )

        {
          csra_assessment: results_payload.as_json,
          csra_cost: {
            increased_license_usage:,
            per_license: cost.format,
            total: (cost * increased_license_usage).format,
          },
          show_enable_code_security_button: show_enable_code_security_button?,
          show_enable_code_security_banner: show_enable_code_security_banner?,
        }
      end

      sig do
        params(
          feature: String,
          view_state: String,
          assessment_number: T.nilable(Integer),
          sra_assessment: T.nilable(::SecretScanning::Models::RiskAssessment::Assessment),
          sra_assessment_list: T.untyped,
          sra_error: T.nilable(T::Boolean),
          csra_assessment: T.nilable(::SecurityProductsEnablement::CodeScanningAssessment),
        ).void
      end
      def render_landing_page(feature:, view_state:, assessment_number: nil, sra_assessment: nil, sra_assessment_list: nil, sra_error: nil, csra_assessment: nil)
        data = {
          backfill_in_progress: security_center_available? ? org.trigger_security_center_reconciliation : false,
          selected_tab: :secret_risk_assessment,
        }

        payload = {
          org: {
            login: org.display_login,
            is_ghas_bundled: org.advanced_security_products_bundled?,
            is_ghas_metered: org.advanced_security_products_metered?,
            active_ghas_trials: org.active_ghas_trials,
            active_ghas_trials_expiration: org.active_ghas_trials_expiration,
          },
          help_url: GitHub.help_url,
          is_enterprise_or_mt: GitHub.enterprise? || GitHub.multi_tenant_enterprise?,
          feature:,
          view_state:,
        }
        payload[:assessment_number] = assessment_number if assessment_number.present?

        if sra_assessment.present?
          payload.merge!(build_sra_payload(
            assessment: sra_assessment,
            assessment_list: sra_assessment_list,
            show_error_banner: sra_error.present?,
          ))
        end

        if csra_assessment.present?
          payload.merge!(build_csra_payload(csra_assessment:))
        end

        add_client_feature_flag(
          [
            ::SecurityProductsEnablement::FeatureFlags::CODE_SECURITY_RISK_ASSESSMENT,
          ],
          entity: org,
        )

        if helpers.show_copilot_chat_entrypoint?
          add_client_feature_flag(
            [
              ::SecurityProductsEnablement::FeatureFlags::RISK_ASSESSMENT_COPILOT_ASSISTIVE,
              ::SecurityProductsEnablement::FeatureFlags::CSRA_COPILOT_ASSISTIVE,
            ],
            entity: org,
          )
        end

        render_react_app(
          title: "Security · Assessments · #{org.display_login}",
          payload:,
          layout: "layouts/security_center/with_sidebar",
          page_data: { data: },
        )
      end

      sig { void }
      def render_secret_protection_index
        assessment, error = latest_sra_assessment_with_error
        assessment_list, _list_error = ::SecretScanning::Services::SecretRiskAssessmentsService.list_assessments(org)

        render_assessment_view(
          assessment:,
          assessment_list:,
          assessment_number: nil,
          show_error_banner: error.present?,
        )
      end

      sig { params(has_private_repos: T.nilable(T::Boolean), repo_ids: T.nilable(T::Array[Integer])).returns(T::Boolean) }
      def show_security_dashboard_button?(has_private_repos: nil, repo_ids: nil)
        if org.plan.business_plus?
          # Enterprise plan: always show button (they have full access)
          true
        elsif org.plan.free?
          # Free plan: never show button (should be blocked by earlier access controls)
          false
        else
          # Team plan (business): show button if enabling security features on private repos
          # OR if they've previously been billed for security features on private repos
          eligibility = ::Repository::SecurityCenterBusinessPlanOrgEligibility.new

          currently_enabling_private_repos = if has_private_repos.present?
            has_private_repos
          elsif repo_ids.present?
            # enabling on public repos doesn't trigger eligibility,
            # make sure at least one private repo is being enabled here to show the button
            org.repositories.where(id: repo_ids, public: false).exists?
          else
            false
          end

          currently_enabling_private_repos || eligibility.enabled?(org)
        end
      end

      sig { void }
      def require_feature_flag
        render_404 unless ::SecretScanning::Features::Org::TokenScanning.new(org).secret_risk_assessment_available?
      end

      sig { void }
      def check_secret_risk_assessments_permission
        return render_404 unless this_organization
        return render_404 unless current_user
        render_404 unless ::SecurityProducts::AccessControl::RiskAssessments.new(org).has_access_to_risk_assessments?(current_user)
      end

      sig { returns(Organization) }
      def org
        this_organization
      end

      sig { returns([T.nilable(::SecretScanning::Models::RiskAssessment::Assessment), T.untyped]) }
      memoize def latest_sra_assessment_with_error
        ::SecretScanning::Services::SecretRiskAssessmentsService.get_latest_assessment_for_org(org, current_user)
      end

      sig { returns(T.nilable(::SecretScanning::Models::RiskAssessment::Assessment)) }
      def latest_sra_assessment
        latest_sra_assessment_with_error.first
      end

      sig { returns(T.nilable(::SecurityProductsEnablement::CodeScanningAssessment)) }
      memoize def latest_csra_assessment
        ::SecurityProductsEnablement::CodeScanningAssessment
          .where(owner_id: org.id, status: [:completed, :pending])
          .order(number: :desc)
          .first
      end

      sig { returns(T::Boolean) }
      def sra_eligible?
        sra = latest_sra_assessment
        return true if sra.nil? || sra.can_request_another_assessment
        FeatureFlag.vexi.enabled?(::SecretScanning::Features::FeatureFlagHelper::FeatureFlags::ASSESSMENT_RESCAN, org, default: false)
      end

      sig { returns(T.nilable(DateTime)) }
      def sra_cooldown_ends_at
        return nil if sra_eligible?
        latest_sra_assessment&.next_request_available_at
      end

      sig { returns(T::Boolean) }
      def csra_eligible?
        csra = latest_csra_assessment
        return true if csra.nil? || csra.can_request_another_assessment?
        # Never allow bypass when an assessment is still in progress
        return false if csra.pending?
        FeatureFlag.vexi.enabled?(::SecurityProductsEnablement::FeatureFlags::CSRA_COOLDOWN_BYPASS, org, default: false)
      end

      sig { returns(T.nilable(Time)) }
      def csra_cooldown_ends_at
        return nil if csra_eligible?
        latest_csra_assessment&.cooldown_ends_at
      end

      sig { returns(T::Hash[Symbol, T.nilable(T::Hash[Symbol, T.untyped])]) }
      def build_eligibility_payload
        sra = latest_sra_assessment

        csra_payload = if csra_feature_flag_enabled?
          csra = latest_csra_assessment
          {
            eligible: csra_eligible?,
            has_prior_assessment: csra.present?,
            last_assessment_date: csra&.created_at&.iso8601,
            cooldown_ends_at: csra_cooldown_ends_at&.iso8601,
          }
        end

        {
          sra: {
            eligible: sra_eligible?,
            has_prior_assessment: sra.present?,
            last_assessment_date: sra&.requested_at&.iso8601,
            cooldown_ends_at: sra_cooldown_ends_at&.iso8601,
          },
          csra: csra_payload,
        }
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
        show_enable_feature_button?(config_enabled: GitHub.configuration_secret_scanning_enabled?, purchased: org.secret_protection_purchased?)
      end

      sig { returns(T::Boolean) }
      def show_enable_secret_protection_banner?
        return true unless ::SecretScanning::Features::Org::TokenScanning.new(org).assessments_check_all_repos_enabled?

        GitHub.dogstats.increment(
          "secret_scanning.risk_assessment.all_repos_enabled.security_center_available",
          tags: [
          "plan:#{org.plan.business? ? "team" : "other"}",
          "security_center_available:#{security_center_available?}",
          ],
        )

        return true unless security_center_available?

        !secret_scanning_completely_enabled?
      end

      sig { returns(T::Boolean) }
      def show_enable_code_security_button?
        show_enable_feature_button?(config_enabled: GitHub.code_scanning_enabled?, purchased: org.code_security_purchased?)
      end

      sig { returns(T::Boolean) }
      def show_enable_code_security_banner?
        return true unless code_scanning_completely_enabled?
        return true unless security_center_available?

        false
      end

      sig { returns(T::Boolean) }
      memoize def code_scanning_completely_enabled?
        org.code_scanning_enabled_in_all_repos?
      end

      sig { returns(T::Boolean) }
      memoize def security_center_available?
        available = ::SecurityCenter::SecurityFeatures.security_center_available?(org)

        if available
          GitHub.logger.info(
            "security center available, checking enablement status for org",
            {
              "code.namespace" => self.class.name,
              "code.function" => __method__,
              "org.id" => org.id,
              "plan" => (org.plan.business? ? "team" : "other"),
            },
          )
        end

        available
      end

      sig do
        params(
          sku: String,
          license: T.untyped,
          show_error_banner: T::Boolean,
        ).returns(T::Hash[Symbol, T.untyped])
      end
      def common_payload(sku:, license:, show_error_banner:)
        cost = org.advanced_security_price_for_sku(sku: sku, seats: 1)
        increased_license_usage = license.seat_usage_increase_if_enabled_for_all_repos

        {
          org: {
            login: org.display_login,
            is_ghas_bundled: org.advanced_security_products_bundled?,
            is_ghas_metered: org.advanced_security_products_metered?,
            active_ghas_trials: org.active_ghas_trials,
            active_ghas_trials_expiration: org.active_ghas_trials_expiration,
          },
          cost: {
            increased_license_usage:,
            per_license: cost.format,
            total: (cost * increased_license_usage).format,
          },
          help_url: GitHub.help_url,
          is_enterprise_or_mt: GitHub.enterprise? || GitHub.multi_tenant_enterprise?,
          show_error_banner:,
        }
      end

      sig { params(config_enabled: T::Boolean, purchased: T::Boolean).returns(T::Boolean) }
      def show_enable_feature_button?(config_enabled:, purchased:)
        return true unless GitHub.enterprise?
        return false unless config_enabled
        return org.advanced_security_purchased? if org.advanced_security_products_bundled?

        purchased
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

        payload = build_sra_payload(
          assessment: assessment,
          assessment_list: assessment_list,
          show_error_banner: show_error_banner,
        )

        # Add assessment number only for show action
        payload[:number] = assessment_number.to_i if assessment_number.present?

        render_react_app(
          title: "Security · Assessments · #{org.display_login}",
          payload: payload,
          layout: "layouts/security_center/with_sidebar",
          page_data: { data: },
          app_payload_generator: -> {
            copilot_chat_available = helpers.show_copilot_chat_entrypoint?
            {
              enabled_features: {
                code_security_risk_assessment: FeatureFlag.vexi.enabled?(::SecurityProductsEnablement::FeatureFlags::CODE_SECURITY_RISK_ASSESSMENT, org, default: false),
                risk_assessment_copilot_assistive: copilot_chat_available && FeatureFlag.vexi.enabled?(::SecurityProductsEnablement::FeatureFlags::RISK_ASSESSMENT_COPILOT_ASSISTIVE, org, default: false),
                csra_copilot_assistive: copilot_chat_available && FeatureFlag.vexi.enabled?(::SecurityProductsEnablement::FeatureFlags::CSRA_COPILOT_ASSISTIVE, org, default: false),
              }
            }
          }
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
        ApplicationRecord::SecurityProductsEnablement,
        ApplicationRecord::Billing,
        ApplicationRecord::Copilot,
        ApplicationRecord::Authnd,
        only: [
          :index,
          :show,
          :json,
          :csra_json,
          :eligibility,
          :results_csv,
          :has_config_conflict,
          :has_code_scanning_config_conflict,
          :committer_count,
        ],
      )
    end
  end
end
