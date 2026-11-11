# typed: true
# frozen_string_literal: true

class MergeQueues::StatusesController < AbstractRepositoryController
  include MergeQueues::SharedControllerMethods

  before_action :merge_queue_required
  before_action :merge_queue_entry_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show], optional: true

  def show
    render partial: "merge_queue/entry_status", locals: {
      entry: entry,
      pull_request: entry.pull_request,
      repository: current_repository,
      merge_queue: merge_queue,
    }
  end

  private

  def merge_queue_entry_required
    entry
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def entry # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @entry ||= merge_queue.entries.find(params[:entry_id])
  end
end
