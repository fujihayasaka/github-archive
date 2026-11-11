# typed: true
# frozen_string_literal: true

class Actions::WorkflowsController < AbstractRepositoryController
  include ::ActionsControllerMethods

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Configurations,
    only: [:index]

  def index
    if actions_workflow_filtering_enabled?
      workflow_records = current_repository.workflows.not_deleted.most_recent.limit(50).preload(:pinned_workflow)
      workflow_names = workflow_records.filter_map { |w| w.name.presence }.uniq
      pinned_names = Set.new(workflow_records.select(&:is_pinned?).filter_map { |w| w.name.presence })
    else
      workflow_names = current_repository.workflows.not_deleted.most_recent.limit(50).pluck(:name).uniq.select(&:present?)
      pinned_names = Set.new
    end

    search_query = params[:q].to_s
    if search_query.present?
      workflow_names = workflow_names.select { |name| name.downcase.include?(search_query.downcase) }
    end

    respond_to do |format|
      format.any(:html, :html_fragment) do
        render "actions/workflows/index",
          layout: false,
          formats: [:html, :html_fragment],
          locals: {
            selected_filename: params[:selected_filename],
            workflows: workflow_names,
            pinned_workflows: pinned_names,
            workflow_run_filters: workflow_run_filters
          }
      end

      format.json do
        render json: workflow_names.map { |name| Search::ParsedQuery.encode_value(name) }
      end
    end
  end
end
