# typed: true
# frozen_string_literal: true

class MergeQueuesController < AbstractRepositoryController
  include GitHub::Memoizer
  include MergeQueues::SharedControllerMethods

  before_action :merge_queue_required
  before_action :ensure_admin_access, only: [:clear]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Spokes,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Ballast,
    ApplicationRecord::Pages,
    only: [:show]

  depends_on_clusters ApplicationRecord::Memex,
    ApplicationRecord::Copilot,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    optional: true, only: [:show]

  def show
    render "merge_queue/show", locals: {
      recent_merge_histogram_days: MergeQueues::SharedControllerMethods::RECENT_MERGE_HISTOGRAM_DAYS,
      merge_queue: merge_queue,
      recent_merges_histogram: recent_merges_histogram,
      up_next_entries_for_display: up_next_entries_for_display,
      page: current_page,
      per_page: params[:per_page],
      active_merge_group:,
    }
  end

  def clear # rubocop:todo GitHub/UseRestfulActions
    merge_queue.force_clear(actor: current_user, async: true)
    flash[:notice] = "Merge queue is being cleared"
  rescue ActiveRecord::ActiveRecordError => error
    error_details = {
      "gh.repo.id": current_repository.id,
      "gh.merge_queue.id": merge_queue.id
    }
    if (record = error.try(:record)) && record.errors.present?
      Failbot.push_sensitive("gh.merge_queue.record_errors": record.errors)
    end
    Failbot.report(error, error_details)
    flash[:error] = "Unable to clear merge queue"
  ensure
    redirect_to merge_queue_path(current_repository.owner, current_repository, merge_queue.branch)
  end
end
