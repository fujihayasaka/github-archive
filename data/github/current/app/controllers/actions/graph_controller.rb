# typed: true
# frozen_string_literal: true

class Actions::GraphController < AbstractRepositoryController
  include ActionsControllerMethods

  layout "repository"

  before_action :actions_enabled_for_repo?
  before_action :should_show_selected_workflow_run?

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::ActionsEnvironments,
    only: [:job]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::ActionsEnvironments,
    only: [:matrix]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:job],
    optional: true

  def job # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless request.xhr?

    graph(current_execution).stages.each do |stage|
      stage.groups.each do |group|
        group.jobs.each do |job|
          if job.id.to_s == params[:job_id]
            respond_to do |format|
              format.html do
                return render(Actions::Graph::JobComponent.new(job: job, workflow_run: workflow_run, parent_group: group.dom_id), layout: false)
              end
            end
          end
        end
      end
    end

    render_404
  end

  def matrix # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless request.xhr?

    execution = current_execution(params[:attempt])
    retry_blankstate = !!(execution.present? && workflow_run&.processing_retry?)
    graph(execution).stages.each do |stage|
      stage.groups.each do |group|
        if group.matrix? && group.id_hash == params[:matrix_id_hash]
          respond_to do |format|
            format.html do
              return render(
                Actions::Graph::MatrixComponent.new(
                  group: group,
                  workflow_run: workflow_run,
                  expanded: params[:expanded] == "true",
                  execution: execution,
                  retry_blankstate: retry_blankstate,
                  pull_request_number: params[:pr]),
                layout: false)
            end
          end
        end
      end
    end

    render_404
  end

  private

  def workflow_run # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @workflow_run ||= Actions::WorkflowRun.with_execution_graph.find_by(repository: current_repository, id: params[:workflow_run_id])
  end

  def graph(execution)
    @graph ||= workflow_run.graph(execution: execution, include_deployments: true)
  end

  def current_execution(attempt = nil)
    if attempt.present?
      Actions::WorkflowRunExecution.with_execution_graph.find_by(repository: current_repository, workflow_run_id: params[:workflow_run_id], attempt: attempt)
    else
      workflow_run.latest_workflow_run_execution_with_graph
    end
  end

end
