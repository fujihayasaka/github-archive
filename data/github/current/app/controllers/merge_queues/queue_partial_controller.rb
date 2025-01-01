# typed: true
# frozen_string_literal: true

class MergeQueues::QueuePartialController < AbstractRepositoryController
  extend T::Sig
  include GitHub::Memoizer
  include MergeQueues::SharedControllerMethods

  before_action :merge_queue_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::IssuesPullRequests,
    only: [:show]

  def show
    render partial: "merge_queue/queue", locals: {
      recent_merge_histogram_days: MergeQueues::SharedControllerMethods::RECENT_MERGE_HISTOGRAM_DAYS,
      merge_queue: merge_queue,
      recent_merges_histogram: recent_merges_histogram,
      up_next_entries_for_display: up_next_entries_for_display,
      page: current_page,
      per_page: params[:per_page],
      active_merge_group:,
    }
  end
end
