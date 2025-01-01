# typed: true
# frozen_string_literal: true

class MergeQueues::EntryEditComponent < ApplicationComponent
  # entry - a MergeQueueEntry in the specified merge queue
  # repository - the Repository with the merge queue
  # merge_queue - a MergeQueue in the specified repository
  # pull_request - the PullRequest represented by the given merge queue entry
  # repo_merge_queue_enabled - optional Boolean indicating whether merge queues are enabled on the given repository;
  #                            if nil, will be calculated
  def initialize(entry:, repository:, merge_queue:, pull_request:, repo_merge_queue_enabled: nil)
    @entry = entry
    @repository = repository
    @merge_queue = merge_queue
    @pull_request = pull_request
    @repo_merge_queue_enabled = repo_merge_queue_enabled
  end

  private

  attr_reader :entry, :repository, :pull_request

  def render?
    return false unless pull_request
    return false if entry.blank?
    return false unless repo_merge_queue_enabled?

    true
  end

  def repo_merge_queue_enabled?
    if @repo_merge_queue_enabled.nil?
      @repo_merge_queue_enabled = repository.merge_queue_enabled?
    else
      @repo_merge_queue_enabled
    end
  end

  def show_solo_merge_option?
    !entry.solo? && @merge_queue.requires_deployments_before_merging?
  end

  def show_solo_merge_warning?
    show_solo_merge_option? && FeatureFlag.vexi.enabled?(:warn_before_selecting_solo_merge, @repository, default: false)
  end

  def show_jump_queue_option?
    !entry.jump_queue? && pull_request.can_jump_merge_queue?(current_user)
  end

  def menu_id
    "queue-menu-#{@pull_request.number}"
  end
end
