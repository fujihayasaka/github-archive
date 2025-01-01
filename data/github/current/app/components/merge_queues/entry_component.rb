# typed: true
# frozen_string_literal: true

class MergeQueues::EntryComponent < ApplicationComponent
  include AvatarHelper
  include StatusHelper
  include PullRequestsHelper

  # entry - a MergeQueueEntry in the specified merge queue
  # pull_request - the PullRequest associated with the merge queue entry
  # repository - the Repository with the merge queue
  # locked - Boolean indicating if the merge group is locked
  # merge_queue - a MergeQueue in the specified repository
  # display_entry_ci_status - Boolean indicating whether to show the entry's CI status (passing, failing, etc.)
  def initialize(entry:, pull_request:, repository:, merge_queue:, locked: false, display_entry_ci_status: true, last_entry_in_list: false)
    @entry = entry
    @pull_request = pull_request
    @repository = repository
    @merge_queue = merge_queue
    @locked = !!locked
    @display_entry_ci_status = !!display_entry_ci_status
    @last_entry_in_list = !!last_entry_in_list
  end

  private

  attr_reader :repository, :last_entry_in_list, :entry

  memoize def merge_queue
    GitHub::PrefillAssociations.prefill_associations(@merge_queue, [
      :protected_branch,
      :repository,
    ], available_records: [@repository])
    @merge_queue
  end

  memoize def pull_request
    GitHub::PrefillAssociations.prefill_associations(@pull_request, [
      :repository,
      :issue,
      :user,
    ], available_records: [current_user, merge_queue.repository])
    @pull_request
  end

  def locked?
    @locked
  end

  def display_entry_ci_status?
    @display_entry_ci_status
  end

  def render?
    return false if @pull_request.blank?
    return false unless GitHub.merge_queues_enabled?
    return false if @entry.blank?
    return false if @repository.blank?
    return false if @merge_queue.blank?

    repo_merge_queue_enabled?
  end

  memoize def repo_merge_queue_enabled?
    repository.merge_queue_enabled?
  end

  def enqueued_by_viewer?
    return false unless logged_in?
    entry.enqueuer_id == current_user.id
  end

  def enqueued_by_author?
    entry.enqueuer_id == pull_request.user.id
  end

  memoize def mergeable?
    entry.mergeable?
  end

  memoize def pull_request_label_names
    Set.new(pull_request.labels.select(:name).map(&:name))
  end

  def viewer_can_admin_entry?
    entry.adminable_by?(current_user)
  end
end
