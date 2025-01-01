# typed: true
# frozen_string_literal: true

class Stafftools::RepositoryOrchestrationsController < StafftoolsController
  before_action :ensure_repo_exists
  before_action :ensure_can_retry_orchestration, only: :show

  layout "layouts/stafftools/repository/overview"

  depends_on_clusters ApplicationRecord::Mysql1,
  ApplicationRecord::IamAbilities,
  ApplicationRecord::Repositories,
  ApplicationRecord::Ballast,
  ApplicationRecord::Collab,
  ApplicationRecord::Mysql2,
  ApplicationRecord::NotificationsEntries,
  ApplicationRecord::Mysql5,
  ApplicationRecord::IssuesPullRequests,
  ApplicationRecord::Configurations,
  ApplicationRecord::Billing,
  ApplicationRecord::Spokes,
  only: [:show, :index]

  depends_on_clusters ApplicationRecord::Copilot,
  only: [:index, :show], optional: true

  def index
    # this is a bit gross but temporary
    # we need to look at both repositories and ballast tables because we can
    # toggle between them via a feature flag
    orchestrations = RepositoryOrchestration.most_recent_for_repository(current_repository.id).to_a

    @repository_orchestrations = orchestrations.paginate \
      page: params[:page] || 1,
      per_page: 25

    render "stafftools/repository_orchestrations/index"
  end

  def show
    id = params[:id].to_i
    orchestration = RepositoryOrchestration.where(id: id, repository_id: current_repository.id).first

    render "stafftools/repository_orchestrations/show", locals: { repository_orchestration: orchestration }
  end

  def retry # rubocop:todo GitHub/UseRestfulActions
    # retry, if appropriate. The validation checks are done in the method
    current_orchestration&.retry_failed_orchestration

    url = "/stafftools/repositories/#{current_repository.name_with_display_owner}/repository_orchestrations/#{current_orchestration.id}"
    redirect_to url
  end

  private

  memoize def current_orchestration
    id = (params[:id] || params[:repository_orchestration_id]).to_i
    RepositoryOrchestration.where(id: id, repository_id: current_repository.id).first
  end

  def ensure_can_retry_orchestration
    # we need a write connection because it may set the orchestration state to :abandoned
    # if the orchestration has failed but a retry is not allowed
    ActiveRecord::Base.connected_to(role: :writing) do
      current_orchestration&.can_retry_failed_orchestration?
      # refresh to get the new state
      current_orchestration.reload
    end
  end
end
