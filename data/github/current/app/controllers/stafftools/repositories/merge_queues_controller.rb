# typed: true
# frozen_string_literal: true

class Stafftools::Repositories::MergeQueuesController < StafftoolsController
  include MergeQueues::SharedControllerMethods

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
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show],
    optional: true

  MERGE_GROUPS_PER_PAGE = 5
  QUEUE_ENTRIES_PER_PAGE = 15

  before_action :ensure_repo_exists
  before_action :ensure_merge_queue_exists

  layout "layouts/stafftools/repository/overview"

  def show
    render(Stafftools::Repositories::MergeQueueComponent.new(
      merge_queue:,
      repository: current_repository,
      page: current_page,
      per_page: (params[:per_page] || QUEUE_ENTRIES_PER_PAGE).to_i,
    ))
  end

  def unlock_group # rubocop:todo GitHub/UseRestfulActions
    result = MergeQueues.unlock!(
      repository: current_repository,
      branch: merge_queue.branch,
      actor: current_user,
      merge_queue:,
    )

    case result
    when MergeQueues::Service::Unlock::Result::NextGroupEmpty
      flash[:error] = "Cannot unlock queue entries: there is no group to unlock"
    when MergeQueues::Service::Unlock::Result::NextGroupNotLocked
      flash[:error] = "Cannot unlock queue entries: the next group is not locked"
    when MergeQueues::Service::Unlock::Result::Success
      flash[:notice] = "Queue entries unlocked"
    else
      T.absurd(result)
    end

    redirect_to_merge_queue
  end

  def clear # rubocop:todo GitHub/UseRestfulActions
    clear_locked_entries = params[:clear_locked_entries] != "false"
    MergeQueues.clear!(
      repository: current_repository,
      branch: merge_queue.branch,
      actor: current_user,
      clear_locked_entries:
    )

    flash[:notice] = "Clearing merge queue for #{merge_queue.branch}"
    redirect_to_merge_queue
  end

  private

  def redirect_to_merge_queue
    redirect_to stafftools_merge_queue_path(current_repository.owner_display_login, current_repository, merge_queue.branch)
  end

  def ensure_merge_queue_exists
    merge_queue.present?
  end
end
