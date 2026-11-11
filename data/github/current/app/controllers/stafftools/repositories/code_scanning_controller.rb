# typed: true
# frozen_string_literal: true

class Stafftools::Repositories::CodeScanningController < StafftoolsController
  before_action :dotcom_required # limiting to dotcom so only GitHub staff can access
  before_action :ensure_repo_exists

  around_action :set_log_context

  layout "layouts/stafftools/repository/overview"

  def show
    render "stafftools/repositories/code_scanning", locals: {
      alert_counts: {
        open: code_scanning_open_alerts_count,
        closed: code_scanning_closed_alerts_count,
        total: code_scanning_total_alerts_count,
      },
      analyses_count: code_scanning_analyses_count,
    }
  end

  def trigger_reconciliation # rubocop:todo GitHub/UseRestfulActions
    source_event = "code_scanning.stafftools.reconcile_repo"

    current_repository.refresh_code_scanning_status
    SecurityOverviewAnalytics::Reconciliation::CodeScanningAlertsDeviationDetectionJob.perform_later(repository_id: current_repository.id, force: true)
    if security_center_sync_eligible_owner?
      SecurityCenter::RepositorySyncJob.perform_later(
        repository_id: current_repository.id,
        source_event: source_event,
        feature_type: "code_scanning",
      )
    end

    GitHub.logger.info(
      "Code scanning reconciliation requested from stafftools",
      "code.namespace": self.class.name,
      "code.function": __method__,
      "gh.repo.id": current_repository.id,
      "gh.security_center.feature_type": "code_scanning",
      "gh.security_center.source_event": source_event,
    )

    redirect_to code_scanning_stafftools_repository_path(current_repository.owner, current_repository), flash: { notice: "Code scanning reconciliation scheduled." }
  end

  def delete_alerts # rubocop:todo GitHub/UseRestfulActions
    unless repository_name_confirmation_matches?
      return redirect_to code_scanning_stafftools_repository_path(current_repository.owner, current_repository), flash: {
        error: "Repository name confirmation did not match. Alerts were not deleted.",
      }
    end

    response = GitHub::Turboscan.delete_alerts(repository_id: current_repository.id)
    if response.nil?
      return redirect_to code_scanning_stafftools_repository_path(current_repository.owner, current_repository), flash: {
        error: "Unable to request alert deletion at this time.",
      }
    end

    twirp_error = response.error
    if twirp_error
      return redirect_to code_scanning_stafftools_repository_path(current_repository.owner, current_repository), flash: {
        error: "Unable to request alert deletion: #{twirp_error.msg}",
      }
    end

    GitHub.logger.info(
      "Code scanning alert deletion requested from stafftools",
      "code.namespace": self.class.name,
      "code.function": __method__,
      "gh.repo.id": current_repository.id,
    )

    redirect_to code_scanning_stafftools_repository_path(current_repository.owner, current_repository), flash: {
      notice: "Alert deletion requested. This endpoint is currently under construction.",
    }
  rescue StandardError => error
    GitHub.logger.warn(
      "Failed to delete code scanning alerts",
      "code.namespace": self.class.name,
      "code.function": __method__,
      "gh.repo.id": current_repository.id,
      "error.message": error.message,
      "error.class": error.class.name,
    )

    redirect_to code_scanning_stafftools_repository_path(current_repository.owner, current_repository), flash: {
      error: "Unable to request alert deletion at this time.",
    }
  end

  private

  def security_center_sync_eligible_owner?
    owner = current_repository.owner
    return false if owner.nil?

    owner.organization? || SecurityCenter::FeatureFlagHelper.allows_emu_owned_repositories?(owner)
  end

  def set_log_context
    GitHub.logger.with_named_tags(
      "enduser.id": current_user.display_login,
      "gh.enduser.id": current_user.id,
      "gh.repo.id": current_repository.id,
      "gh.repo.name": current_repository.name,
      "gh.owner.id": current_repository.owner_id,
      "gh.owner.login": current_repository.owner_display_login,
    ) do
      yield
    end
  end

  memoize def code_scanning_alert_info
    GitHub::Turboscan.alerts_by_repo(
      owner_ids: [current_repository.owner_id],
      repository_ids: [current_repository.id],
      limit: 1,
    )&.data
  rescue StandardError => error
    GitHub.logger.warn(
      "Failed to fetch code scanning alert info",
      "code.namespace": self.class.name,
      "code.function": __method__,
      "gh.repo.id": current_repository.id,
      "error.message": error.message,
      "error.class": error.class.name,
    )

    nil
  end

  def code_scanning_open_alerts_count
    code_scanning_alert_info&.open_count || 0
  end

  def code_scanning_closed_alerts_count
    code_scanning_alert_info&.resolved_count || 0
  end

  def code_scanning_total_alerts_count
    code_scanning_open_alerts_count + code_scanning_closed_alerts_count
  end

  def repository_name_confirmation_matches?
    expected = current_repository.name_with_display_owner
    provided = params[:verify].to_s

    provided.casecmp?(expected)
  end

  memoize def code_scanning_analyses_count
    GitHub::Turboscan.analyses(repository_id: current_repository.id, limit: 1)&.data&.total_count || 0
  rescue StandardError => error
    GitHub.logger.warn(
      "Failed to fetch code scanning analyses count",
      "code.namespace": self.class.name,
      "code.function": __method__,
      "gh.repo.id": current_repository.id,
      "error.message": error.message,
      "error.class": error.class.name,
    )

    0
  end

  depends_on_clusters \
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    only: [:show]
end
