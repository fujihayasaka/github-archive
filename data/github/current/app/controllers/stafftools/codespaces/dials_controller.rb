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
      Codespaces::Dials::BillingWorkerCount.new(force_cache_miss: true),
      Codespaces::Dials::BillingWorkerForSlowQueuesCount.new(force_cache_miss: true),
      Codespaces::Dials::ExtendedRateLimitDurationMinutes.new(force_cache_miss: true),
      Codespaces::Dials::ExtendedRateLimitMaxOperations.new(force_cache_miss: true),
      Codespaces::Dials::MaximumCoreCountPerCodespaceForUntrustedUser.new(force_cache_miss: true),
      Codespaces::Dials::MaximumCoreCountPerCodespaceForNeutralUser.new(force_cache_miss: true),
      Codespaces::Dials::MaximumCoreCountPerCodespaceForNeutralOrg.new(force_cache_miss: true),
      Codespaces::Dials::MaximumCoreCountPerCodespaceForUntrustedOrg.new(force_cache_miss: true),
      Codespaces::Dials::CopilotWorkspaceUsageLimitSeconds.new(force_cache_miss: true),
      Codespaces::Dials::MaximumTotalCopilotWorkspaceCodespacesForUser.new(force_cache_miss: true),
      Codespaces::Dials::MaximumCopilotWorkspaceInstancesForUser.new(force_cache_miss: true),
      Codespaces::Dials::MaximumCopilotWorkspaceCoresForUser.new(force_cache_miss: true),
      Codespaces::Dials::WorkspaceEditorIndividualUsageLimitSeconds.new(force_cache_miss: true),
      WorkspaceEditor::Cloudspaces::Public.max_instances_for_user_global_setting,
      WorkspaceEditor::Cloudspaces::Public.idle_timeout_global_setting,
    ]
  end

  def visible_dials_by_key
    visible_dials.map { |dial| [dial.key, dial] }.to_h
  end

  def require_codespaces_developer
    render_404 unless GitHub.flipper[:codespaces_developer].enabled?(current_user)
  end
end
