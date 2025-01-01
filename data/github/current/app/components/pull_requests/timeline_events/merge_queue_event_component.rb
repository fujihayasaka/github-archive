# typed: strict
# frozen_string_literal: true

module PullRequests::TimelineEvents
  class MergeQueueEventComponent < ApplicationComponent
    include PullRequestsHelper

    # TODO: IssueEvent does not support #message
    sig { returns(T.untyped) }
    attr_reader :issue_event

    sig { returns(PullRequest) }
    attr_reader :pull_request

    sig { returns(T.nilable(MergeQueue)) }
    attr_reader :merge_queue

    sig { returns(Repository) }
    attr_reader :repository

    sig { params(issue_event: IssueEvent, pull_request: PullRequest).void }
    def initialize(issue_event:, pull_request:)
      @issue_event = issue_event
      @pull_request = pull_request
      @merge_queue = T.let(pull_request.merge_queue, T.nilable(MergeQueue))
      @repository = T.let(T.must(pull_request.repository), Repository)
    end

    sig { returns(T::Boolean) }
    def render?
      !merge_event?
    end

    sig { returns(User) }
    def actor
      issue_event.event_actor(viewer: current_user)
    end

    sig { returns(Symbol) }
    def action
      issue_event.event == "added_to_merge_queue" ? :added : :removed
    end

    sig { returns(T::Boolean) }
    memoize def show_commit_status?
      action == :removed && issue_event.before_commit_oid.present?
    end

    sig { returns(String) }
    def event_description
      if action == :added
        return sanitize("added this pull request to the #{merge_queue_link}")
      end

      case reason = removal_reason
      when MergeQueues::Entry::RemovalReason::AlreadyMerged
        sanitize("removed this pull request from the #{merge_queue_link} due to it being already merged")
      when MergeQueues::Entry::RemovalReason::ChecksTimedOut
        sanitize("removed this pull request from the #{merge_queue_link} due to no response for status checks")
      when MergeQueues::Entry::RemovalReason::FailedChecks
        sanitize("removed this pull request from the #{merge_queue_link} due to failed status checks")
      when MergeQueues::Entry::RemovalReason::MergeConflict
        sanitize("removed this pull request from the #{merge_queue_link} due to a conflict with the base branch")
      when MergeQueues::Entry::RemovalReason::Merged
        sanitize("removed this pull request from the #{merge_queue_link} due to the pull request being merged")
      when MergeQueues::Entry::RemovalReason::Manual
        sanitize("removed this pull request from the #{merge_queue_link} due to a manual request")
      when MergeQueues::Entry::RemovalReason::GitTreeInvalid
        sanitize("removed this pull request from the #{merge_queue_link} due to an unknown Git error")
      when MergeQueues::Entry::RemovalReason::Unknown
        sanitize("removed this pull request from the #{merge_queue_link} due to an unknown reason")
      when MergeQueues::Entry::RemovalReason::QueueCleared
        sanitize("removed this pull request from the #{merge_queue_link} due to the queue being cleared")
      when MergeQueues::Entry::RemovalReason::RollBack
        sanitize("removed this pull request from the #{merge_queue_link} due to a roll back")
      when MergeQueues::Entry::RemovalReason::InvalidMergeCommit
        sanitize("removed this pull request from the #{merge_queue_link} due to invalid changes in the merge commit")
      when MergeQueues::Entry::RemovalReason::BranchProtections
        sanitize("removed this pull request from the #{merge_queue_link} due to Branch Protection failures")
      else
        T.absurd(reason)
      end
    end

    sig { returns(String) }
    def merge_queue_link
      if queue = merge_queue
        merge_queue_resource_path = merge_queue_path(repository.owner_display_login, repository, queue.branch)
        render Primer::Beta::Link.new(href: merge_queue_resource_path).with_content("merge queue")
      else
        "merge queue"
      end
    end

    sig { returns(T::Boolean) }
    def any_new_commits_will_not_be_merged?
      return false if action != :added

      pull_request.branch_locked_for_merge_queue?(check_head_ref: true)
    end

    sig { returns(T::Boolean) }
    def merge_event?
      return false if action == :added

      removal_reason == MergeQueues::Entry::RemovalReason::Merged
    end

    sig { returns(MergeQueues::Entry::RemovalReason) }
    memoize def removal_reason
      MergeQueues::Entry::RemovalReason.deserialize(issue_event_message)
    end

    sig { returns(Symbol) }
    def issue_event_message
      issue_event.message ? issue_event.message.to_sym : :unknown
    end

    sig { returns(T::Boolean) }
    def branch_protection_failure?
      removal_reason == MergeQueues::Entry::RemovalReason::BranchProtections
    end
  end
end
