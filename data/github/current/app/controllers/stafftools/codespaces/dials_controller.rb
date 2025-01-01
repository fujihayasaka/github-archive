# typed: true
# frozen_string_literal: true

class Stafftools::Codespaces::DialsController < StafftoolsController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:index, :edit]


  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :edit], optional: true

  before_action :require_codespaces_developer


  def index
    render "stafftools/codespaces/dials/index", locals: { dials: visible_dials_by_key.values }
  end

  def edit
    dial = visible_dials_by_key[params[:id]]

    render "stafftools/codespaces/dials/edit", locals: { dial: dial }
  end

  def update
    dial = visible_dials_by_key[params[:id]]
    dial.value = params[:value]

    if dial.save
      flash[:notice] = "Dial value updated"
      redirect_to action: "edit", id: dial.key
    else
      flash[:error] = "Could not save dial: #{dial.errors.full_messages.join(", ")}"
      render "stafftools/codespaces/dials/edit", locals: { dial: dial }
    end
  end

  private

  def visible_dials
    [
      # Codespaces Billing
      Codespaces::Dials::BillingWorkerCount.new(force_cache_miss: true),
      Codespaces::Dials::BillingWorkerForSlowQueuesCount.new(force_cache_miss: true),
      # Codespaces Indiv Usage
      Codespaces::Dials::ExtendedRateLimitDurationMinutes.new(force_cache_miss: true),
      Codespaces::Dials::ExtendedRateLimitMaxOperations.new(force_cache_miss: true),
      Codespaces::Dials::MaximumCoreCountPerCodespaceForUntrustedUser.new(force_cache_miss: true),
      Codespaces::Dials::MaximumCoreCountPerCodespaceForNeutralUser.new(force_cache_miss: true),
      Codespaces::Dials::MaximumCoreCountPerCodespaceForNeutralOrg.new(force_cache_miss: true),
      Codespaces::Dials::MaximumCoreCountPerCodespaceForUntrustedOrg.new(force_cache_miss: true),
      # Copilot Workspace Capacity
      Codespaces::Dials::CopilotWorkspaceMaxCodespaceUsers.new(force_cache_miss: true),
      Codespaces::Dials::CopilotWorkspaceMaxModelUsers.new(force_cache_miss: true),
      # Copilot Workspace Indiv Usage
      Codespaces::Dials::CopilotWorkspaceUsageLimitSeconds.new(force_cache_miss: true),
      Codespaces::Dials::MaximumTotalCopilotWorkspaceCodespacesForUser.new(force_cache_miss: true),
      Codespaces::Dials::MaximumCopilotWorkspaceInstancesForUser.new(force_cache_miss: true),
      Codespaces::Dials::MaximumCopilotWorkspaceCoresForUser.new(force_cache_miss: true),
      Codespaces::Dials::WorkspaceEditorIndividualUsageLimitSeconds.new(force_cache_miss: true),
      # Workspace Editor Indiv Usage
      WorkspaceEditor::Cloudspaces::Public.max_instances_for_user_global_setting,
      WorkspaceEditor::Cloudspaces::Public.idle_timeout_global_setting,
      # Workbench Indiv Usage
      Workbench::SparkCloudspaces::Public.max_instances_for_free_user_global_setting,
      Workbench::SparkCloudspaces::Public.max_instances_for_paid_user_global_setting,
      Workbench::SparkCloudspaces::Public.idle_timeout_global_setting,
      Workbench::SparkCloudspaces::Public.free_user_usage_limit_seconds_global_setting,
      Workbench::SparkCloudspaces::Public.paid_user_usage_limit_seconds_global_setting,
      Workbench::SparkCloudspaces::Public.extended_user_usage_limit_seconds_global_setting,
      # Agent Sessions Indiv Usage
      CopilotSweAgent::Public.copilot_sessions_polling_interval_seconds,
      CopilotSweAgent::Public.copilot_logs_polling_interval_seconds,
    ]
  end

  def visible_dials_by_key
    visible_dials.map { |dial| [dial.key, dial] }.to_h
  end

  def require_codespaces_developer
    render_404 unless FeatureFlag.vexi.enabled?(:codespaces_developer, current_user, default: false)
  end
end
