# typed: true
# frozen_string_literal: true

class Actions::WorkflowsPartialsController < AbstractRepositoryController
  include ActionsControllerMethods

  around_action :track_and_report_render_view_time, only: [:show]
  around_action :track_and_report_graphql_executions, only: [:show]
  around_action :track_and_report_mysql_executions, only: [:show]
  before_action :login_required, except: [:show]
  before_action :actions_enabled_for_repo?, except: [:show]

  preload_features [:actions_workflow_list_pinning]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::RepositoriesActionsChecks,
    only: [:show, :unpin_workflow_dialogs]

  def show
    fetch_required_workflows = (params[:fetch_required_workflows] == "true")
    workflows = paginated_workflows(current_page, fetch_required_workflows: fetch_required_workflows)

    render partial: "actions/workflows_partials/show", locals: {
      workflow_run_filters: workflow_run_filters,
      workflows: workflows,
      selected_workflow: selected_workflow,
      allow_pinning: allow_pinning?,
      is_mobile: params[:mobile] == "true"
    }
  end

  def unpin_workflow_dialogs # rubocop:todo GitHub/UseRestfulActions
    workflow_ids = Actions::PinnedWorkflow.where(repository_id: current_repository.id).map(&:workflow_id)
    render partial: "actions/workflows_partials/unpin_workflow_dialog", collection: workflow_ids, as: :workflow_id
  end
end
