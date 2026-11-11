# typed: true
# frozen_string_literal: true

module PullRequests
  class StackEntry < ApplicationRecord::Domain::IssuesPullRequests
    include ::Repositories::BelongsToRepository
    include GitHub::Relay::GlobalIdentification

    self.table_name = "pull_request_stack_entries"

    belongs_to_repository_via_domain
    belongs_to :stack, ->(e) { e.nil? ? all : where(repository_id: e.repository_id) },
      class_name: "PullRequests::Stack"
    belongs_to :pull_request, ->(e) { where(repository_id: e.repository_id) }

    validates :repository, :stack, :pull_request, presence: true
    validate :stack_repo_match
    validate :pull_request_repo_match
    validate :max_stack_size, on: :create

    sig { returns(String) }
    def platform_type_name = "PullRequestStackEntry"

    # The stack entry at position - 1 in the same stack. Nil for position 1 entries.
    sig { returns(T.nilable(PullRequests::StackEntry)) }
    def parent_entry
      return nil if position == 1

      self.class.find_by(repository_id:, stack_id:, position: position - 1)
    end

    # The pull request associated with the parent stack entry.
    sig { returns(T.nilable(PullRequest)) }
    def parent_pull_request
      parent_entry&.pull_request
    end

    # Returns true if this entry is at position 1 (no parent) or the parent's
    # pull request has been merged.
    sig { returns(T::Boolean) }
    def parent_merged?
      return true if position == 1

      parent_pull_request&.merged? || false
    end

    private

    sig { void }
    def stack_repo_match
      stack = self.stack
      return if stack.nil?

      if repository_id != stack.repository_id
        errors.add :repository, :mismatch, message: "must match stack's repository"
      end
    end

    sig { void }
    def pull_request_repo_match
      pull_request = self.pull_request
      return if pull_request.nil?

      if repository_id != pull_request.repository_id
        errors.add :repository, :mismatch, message: "must match pull request's repository"
      end

      if pull_request.cross_repo?
        errors.add :pull_request, :cross_repo, message: "must not be cross-repository"
      end
    end

    sig { void }
    def max_stack_size
      stack = self.stack
      return if stack.nil?

      if position > Stack::MAX_NUMBER_OF_ENTRIES
        errors.add :stack, :too_large, message: "exceeds maximum stack size"
      end
    end
  end
end
