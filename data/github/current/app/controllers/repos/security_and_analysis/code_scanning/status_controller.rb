# typed: true
# frozen_string_literal: true

class Repos::SecurityAndAnalysis::CodeScanning::StatusController < AbstractRepositoryController
  skip_before_action :privacy_check

  before_action :manage_security_products_permission_required

  track_latency_slo "p99-ui-request", 3000, only: [:index]
  track_latency_slo "p50-ui-request", 750, only: [:index]

  depends_on_clusters(
    ApplicationRecord::Mysql1,
    ApplicationRecord::Spokes,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Notify,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    ApplicationRecord::RepositoriesActionsChecks,
  )

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  # A poll-include-fragment element will be polling this endpoint until the 1-Click setup comes out of the transient _enabling_ state.
  def index
    if auto_codeql.enabling? || auto_codeql.updating?
      case params[:wait_until]
      # Stage 1: enabling but no workflow run ID yet
      when "has_workflow_run"
        return head(202) if auto_codeql.debuggable_auto_codeql_run_id.blank?
      # Stage 2: still enabling but now with a workflow run ID
      when "completion"
        return head(202)
      end
    end

    # Initial render or Stage 3: completed, either success or failed
    component = CodeScanning::Settings::StatusComponent.new(
      repository: current_repository,
      language_display_names: auto_codeql.language_support.display_names,
      runners_error: auto_codeql.runners_error,
      auto_codeql_onboarding_status: auto_codeql_onboarding_status,
      auto_codeql_detected_languages: auto_codeql.language_support.supported_languages,
      auto_codeql_debuggable_workflow_run_id: auto_codeql.debuggable_auto_codeql_run_id,
      dismissed_auto_codeql_notice: auto_codeql.dismissed_auto_codeql_notice?(
        repository_id: current_repository.id,
        user_id: current_user.id
      ),
      latest_workflow_run_id: auto_codeql.latest_workflow_run_id,
      latest_successful_codeql_analysis_date: auto_codeql.latest_successful_codeql_analysis_date,
      latest_codeql_analysis_is_managed: auto_codeql.latest_codeql_analysis_is_managed?,
      latest_codeql_analysis_date: auto_codeql.codeql_status&.latest_analysis_date,
      latest_codeql_analysis_delivery_origin: auto_codeql.codeql_status&.latest_analysis_delivery_origin,
      codeql_workflow_path: auto_codeql.codeql_workflow_path,
      configuration: auto_codeql.enabled? ? auto_codeql.configuration : auto_codeql.recommended_configuration,
      next_scheduled_run_at: auto_codeql.next_scheduled_run_at,
      is_repo_active: auto_codeql.is_repo_active?,
      auto_codeql_setup_failed: auto_codeql.auto_codeql_failed?,
      debuggable_configuration: auto_codeql.debuggable_configuration,
      has_failed_update: auto_codeql.has_failed_update?,
      latest_debuggable_run_id: auto_codeql.debuggable_auto_codeql_run_id,
      disabling_auto_codeql_restricted_by_security_configuration:,
      enabling_auto_codeql_restricted_by_security_configuration:,
    )
    render(component, layout: false) # rubocop:disable GitHub/RailsControllerRenderLiteral
  end

  def dismiss_auto_codeql_error_notice # rubocop:disable GitHub/UseRestfulActions
    auto_codeql.dismiss_auto_codeql_notice(repository_id: current_repository.id, user_id: current_user.id)
    if request.xhr?
      head :ok
    else
      redirect_to :back
    end
  end

  private

  sig { returns(CodeScanning::AutoCodeql) }
  def auto_codeql # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @auto_codeql ||= CodeScanning::AutoCodeql.new(current_repository)
  end

  def auto_codeql_onboarding_status
    if auto_codeql.updating?
      "updating"
    elsif auto_codeql.waiting?
      "waiting"
    elsif auto_codeql.enabling?
      "enabling"
    elsif auto_codeql.enabled?
      "enabled"
    else
      "disabled"
    end
  end

  def disabling_auto_codeql_restricted_by_security_configuration
    has_enforced_security_configuration? && current_repository.security_configuration&.code_scanning_enabled?
  end

  def enabling_auto_codeql_restricted_by_security_configuration
    has_enforced_security_configuration? && current_repository.security_configuration&.code_scanning_disabled?
  end

  memoize def has_enforced_security_configuration?
    current_repository.owner&.security_configurations_enabled? &&
      current_repository.repository_security_configuration&.enforced?
  end
end
