# typed: true
# frozen_string_literal: true

class Stafftools::Repositories::MergeCommitRequestsController < StafftoolsController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Ballast,
    ApplicationRecord::Spokes,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  before_action :ensure_repo_exists

  layout "stafftools/repository/overview"

  def index
    render Stafftools::Repositories::MergeCommitRequestsComponent.new(repository: current_repository)
  end

  # This is a variation of the standard RESTful action to destroy, and this controller is not large,
  # with little concern over code ownership. As such, I'm disabling UseRestfulActions for this method.
  # However, if we add significantly more to this controller, I'd probably revisit this and pull this out.
  def clear # rubocop:disable GitHub/UseRestfulActions
    MergeCommitRequest.where(repository_id: current_repository.id).destroy_all
    flash[:notice] = "Cleared merge commit requests queue for #{current_repository.name_with_owner}"
    redirect_to :back
  end

  def pause # rubocop:disable GitHub/UseRestfulActions
    MergeCommitRequest.set_paused_for(current_repository)
    flash[:notice] = "Merge commit request processing paused for #{current_repository.name_with_owner}"
    redirect_to :back
  end

  def unpause # rubocop:disable GitHub/UseRestfulActions
    MergeCommitRequest.clear_paused_for(current_repository)
    flash[:notice] = "Merge commit request processing enabled for #{current_repository.name_with_owner}"
    redirect_to :back
  end
end
