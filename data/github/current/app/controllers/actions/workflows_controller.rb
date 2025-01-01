# typed: true
# frozen_string_literal: true

class Actions::WorkflowsController < AbstractRepositoryController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Configurations,
    only: [:index]

  def index
    workflows = current_repository.workflows.not_deleted.most_recent.limit(50).pluck(:name).uniq.filter_map { |name| Search::ParsedQuery.encode_value(name) if name.present? }

    respond_to do |format|
      format.json do
        render json: workflows
      end
    end
  end
end
