# typed: true
# frozen_string_literal: true

module PullRequests
  class PullRequestEnqueuedComponent < ApplicationComponent
    attr_reader :pull, :repository, :user

    def initialize(pull:, repository:, user:)
      @pull = pull
      @repository = repository
      @user = user
    end

    private

    def render?
      queue_entry.present?
    end

    def ahead_in_queue_message_prefix
      case ahead_in_queue_count
      when 0
        "This pull request is at the head of"
      when 1
        "There is 1 pull request ahead of this one in"
      else
        "There are #{ahead_in_queue_count} pull requests ahead of this one in"
      end
    end

    memoize def ahead_in_queue_count
      merge_queue_entries.find_index(queue_entry)
    end

    memoize def queue_entry
      merge_queue_entries.detect { |entry| entry.pull_request_id == pull.id }
    end

    def locked?
      queue_entry&.locked?
    end

    memoize def merge_conflict?
      queue_entry&.blocked_by_merge_conflicts?
    end

    def conflicting_files
      @conflicting_files ||= queue_entry&.conflicting_files
      @conflicting_files ||= []
    end

    memoize def merge_queue_branch
      merge_queue.branch
    end

    memoize def merge_queue
      pull.merge_queue
    end

    memoize def merge_queue_entries
      merge_queue.entries.to_a
    end

    def viewer_can_remove_from_queue?
      queue_entry.adminable_by?(user)
    end
  end
end
