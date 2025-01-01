# typed: true
# frozen_string_literal: true

class Orgs::SecurityAnalysisController < Orgs::Controller
  # Access
  before_action :manage_security_products_permission_required

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::Notify,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    only: [:enableable_repo_counts, :disableable_repo_counts]

  def update
    error_message = UpdateSecuritySettings.perform(current_organization, params, actor: current_user).try(:fetch, :error, nil)
    return redirect_to(:back, flash: { error: error_message }) if error_message.present?

    track_task_completion
    flash[:notice] = "Security settings updated for #{current_organization.name}'s repositories."

    redirect_to settings_org_security_analysis_path(current_organization, show_update_tip: params[:show_update_tip], show_alert_tip: params[:show_alert_tip], tip: get_onboarding_tip)
  end

  def enableable_repo_counts # rubocop:todo GitHub/UseRestfulActions
    GitHub.logger.with_named_tags(
      controller: self.class.name,
      actor: current_user.login, # rubocop:disable GitHub/DoNotAllowLogin used in a logger
      actor_id: current_user.id,
      organization: current_organization.login, # rubocop:disable GitHub/DoNotAllowLogin used in a logger
      owner_id: current_organization.id,
    ) do
      GitHub.dogstats.distribution_time("security_analysis.repo_enablement_count.time", tags: ["feature_type:#{params[:feature_type]}"]) do
        total_repos = RepositorySecurityCenterConfig.where(owner_id: current_organization.id)

        case params[:feature_type]
        when "code_scanning"
          GitHub.logger.info("get eligible repo count for Code Scanning")

          feature_statuses = RepositorySecurityCenterStatus
            .joins(:repository_security_center_config)
            .where(owner_id: current_organization.id, feature_type: "code_scanning_auto_codeql")

          # For bulk enablement specifically, we exclude repos that have an existing manual CodeQL setup. These
          # repos _are_ eligible for CodeQL default setup, and the single-repo enablement confirms the user's intent
          # to override the manual configuration. If we were to ingest the "eligibility" status for these repos,
          # it would break filtering on the Coverage page. For the purposes of this count, we'll approximate this
          # "pseudo-eligibility" excluding repos marked as "enrolled" in the base code scanning feature.
          eligible_statuses = feature_statuses
            .where(scanning_status: "eligible", repository_security_center_config: { archived: false })
            .where.not(repository_id: RepositorySecurityCenterStatus.where(owner_id: current_organization.id, feature_type: "code_scanning", scanning_status: "enrolled").select(:repository_id))

          repos_eligible_for_feature = eligible_statuses.where(repository_security_center_config: { ghas_enabled: true })
          repos_eligible_for_feature = repos_eligible_for_feature.or(eligible_statuses.where(repository_security_center_config: { visibility: "public" })) if GitHub.dotcom_request?
          repos_eligible_for_feature_count = repos_eligible_for_feature.count

          currently_enabled_count = feature_statuses.where(scanning_status: "enrolled").count
          will_be_enabled_count = repos_eligible_for_feature_count

        when "secret_scanning"
          GitHub.logger.info("get eligible repo count for Secret Scanning")

          feature_statuses = RepositorySecurityCenterStatus
            .where(owner_id: current_organization.id, feature_type: "secret_scanning")

          if current_organization.advanced_security_purchased?
            repos_eligible_for_feature = total_repos.where(archived: true)
            repos_eligible_for_feature = repos_eligible_for_feature.or(total_repos.where(visibility: "public")) if GitHub.dotcom_request?
            repos_eligible_for_feature = repos_eligible_for_feature.or(total_repos.where(ghas_enabled: true))
          else
            repos_eligible_for_feature = total_repos.where(visibility: "public")
          end

          currently_enabled_count = feature_statuses.where(scanning_status: "enrolled").count
          will_be_enabled_count = repos_eligible_for_feature.count - currently_enabled_count

        when "push_protection"
          GitHub.logger.info("get eligible repo count for Push Protection")

          feature_statuses = RepositorySecurityCenterStatus
            .where(owner_id: current_organization.id, feature_type: "secret_scanning_push_protection")

          repos_with_ss_enabled = RepositorySecurityCenterStatus.where(owner_id: current_organization.id, feature_type: "secret_scanning", scanning_status: "enrolled")
          repos_eligible_for_feature = total_repos.where(repository_id: repos_with_ss_enabled.select(:repository_id), archived: false)

          currently_enabled_count = feature_statuses.where(scanning_status: "enrolled").count
          will_be_enabled_count = repos_eligible_for_feature.count - currently_enabled_count

        else
          return redirect_to :back
        end

        will_be_enabled_count = 0 if will_be_enabled_count.negative? # this shouldn't happen, but is possible if our records are out of sync

        GitHub.logger.info(
          "render",
          ghas_purchased: current_organization.advanced_security_purchased?,
          total_repos_count: total_repos.count,
          currently_enabled_count: currently_enabled_count,
          will_be_enabled_count: will_be_enabled_count,
          feature_name: params[:feature_type],
        )

        feature_name = case params[:feature_type]
        when "code_scanning"
          "CodeQL default setup"
        else
          params[:feature_type].humanize
        end

        render partial: "orgs/settings/security_analysis_settings_dialog_repo_enablement_count", locals: {
          total_repos_count: total_repos.count,
          currently_enabled_count: currently_enabled_count,
          will_be_enabled_count: will_be_enabled_count,
          feature_name: feature_name,
        }
      end
    end
  end

  def disableable_repo_counts # rubocop:todo GitHub/UseRestfulActions
    GitHub.dogstats.distribution_time("security_analysis.repo_disablement_count.time", tags: ["feature_type:#{params[:feature_type]}"]) do
      security_features = {
        "code_scanning" => :code_scanning_auto_codeql,
        "secret_scanning" => :secret_scanning,
        "push_protection" => :secret_scanning_push_protection,
      }

      if security_features.keys.exclude?(params[:feature_type])
        return redirect_to :back
      end

      currently_enabled_count = RepositorySecurityCenterStatus
        .where({
          owner_id: current_organization.id,
          feature_type: security_features[params[:feature_type]],
          scanning_status: :enrolled
        })
        .count

      feature_name = case params[:feature_type]
      when "code_scanning"
        "CodeQL default setup"
      else
        params[:feature_type].humanize(capitalize: false)
      end

      render partial: "orgs/settings/security_analysis_settings_dialog_repo_disablement_count", locals: {
        feature: feature_name,
        repo_count: currently_enabled_count,
      }
    end
  end

  def default_setup_query_suite_selector # rubocop:todo GitHub/UseRestfulActions
    path = "/code-security/code-scanning/automatically-scanning-your-code-for-vulnerabilities-and-errors/built-in-codeql-query-suites"
    base_url = GitHub.help_url(ghec_exclusive: current_organization.business || current_organization.business_plus?)

    render partial: "orgs/settings/security_analysis_default_setup_query_suite_selector", locals: {
      recommended_query_suite: CodeScanning::AutoCodeql.recommended_query_suite(current_organization),
      help_url: "#{base_url}#{path}",
      suite_options: CodeScanning::AutoCodeql.query_suite_options(current_organization),
    }
  end

  private

  def current_organization # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @current_organization if defined? @current_organization
    @current_organization = Organization.find_by_login(org_login_param)
  end

  def target_for_conditional_access
    current_organization
  end

  def get_onboarding_tip
    referrer = Addressable::URI.parse(request.referrer)
    return nil unless referrer && referrer.domain == request.domain
    return nil unless referrer.query_values
    referrer.query_values["tip"]
  end

  def track_task_completion
    if params[:advanced_security] == "enable_all"
      OnboardingTasks::AdvancedSecurity::EnableAdvancedSecurity.new(taskable: current_organization, user: current_user).complete
    end
    if params[:secret_scanning] == "enable_all"
      OnboardingTasks::AdvancedSecurity::EnableSecretScanning.new(taskable: current_organization, user: current_user).complete
    end
    if params[:code_scanning] == "enable_all"
      OnboardingTasks::AdvancedSecurity::EnableCodeScanning.new(taskable: current_organization, user: current_user).complete
    end
    if params[:secret_scanning_push_protection] == "enable_all"
      OnboardingTasks::AdvancedSecurity::EnablePushProtection.new(taskable: current_organization, user: current_user).complete
    end
  end
end
