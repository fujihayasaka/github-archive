# typed: true
# frozen_string_literal: true

module PullRequests
  class Stack < ApplicationRecord::Domain::IssuesPullRequests
    include ::Repositories::BelongsToRepository
    include GitHub::Memoizer
    include GitHub::Relay::GlobalIdentification

    self.table_name = "pull_request_stacks"

    class ConflictError < StandardError; end

    belongs_to_repository_via_domain
    has_many :entries, ->(s) { where(repository_id: s.repository_id).order(position: :asc) },
      class_name: "PullRequests::StackEntry",
      inverse_of: :stack,
      dependent: :destroy
    has_many :pull_requests, through: :entries

    validates :number, presence: true
    validate :max_stack_size

    MAX_NUMBER_OF_ENTRIES = 100

    sig { returns(String) }
    def platform_type_name = "PullRequestStack"

    sig { returns(Integer) }
    def entry_count = entries.size

    sig { params(start_pull: PullRequest).returns(T::Array[PullRequest]) }
    def pulls_from(start_pull)
      relevant_entries = entries.drop_while { _1.pull_request_id != start_pull.id }
      GitHub::PrefillAssociations.prefill_associations(
        relevant_entries,
        { pull_request: :issue },
        available_records: [start_pull],
      )
      relevant_entries.filter_map(&:pull_request)
    end

    sig { params(start_pull: PullRequest).returns(T::Array[PullRequest]) }
    def unmerged_pulls_from(start_pull)
      entries
        .where("position <= ?", start_pull.stack_position.to_i)
        .order(position: :asc)
        .includes(:pull_request)
        .filter_map(&:pull_request)
        .reject(&:merged?)
    end

    # Returns if there are any stack entries that still need to be merged, but are out of date with base branch
    # This will exclude PRs that are:
    # - actively being auto-merged
    # - sitting in the merge queue
    # - merged
    sig { returns(T::Boolean) }
    def has_outdated_stack_entries?
      pulls = entries.includes(:pull_request).filter_map(&:pull_request)
      ActiveRecord::Associations::Preloader.new(
        records: pulls,
        associations: [:issue, :auto_merge_request, :merge_queue_entry],
      ).call
      pulls.select(&:stack_changes_allowed?).any?(&:behind_base?)
    end

    # The lowest-position entry whose pull request has not yet been merged.
    # This is the current "bottom" of the active stack — everything below it
    # has already landed on the base branch.
    sig { returns(T.nilable(PullRequests::StackEntry)) }
    def current_base_entry
      entries.order(position: :asc).find { |e| !e.pull_request&.merged? }
    end

    sig { returns(T.nilable(String)) }
    def base_sha
      return nil unless base_pull_request = self.base_pull_request
      base_pull_request.base_sha
    end

    sig { returns(T.nilable(Repository)) }
    memoize def base_repository
      return nil unless base_pull_request = self.base_pull_request
      base_pull_request.base_repository
    end

    private

    sig { returns(T.nilable(PullRequest)) }
    memoize def base_pull_request
      current_base_entry&.pull_request
    end

    sig { void }
    def max_stack_size
      if entries.size > MAX_NUMBER_OF_ENTRIES
        errors.add :entries, :too_large, message: "exceeds maximum stack size"
      end
    end
  end
end
