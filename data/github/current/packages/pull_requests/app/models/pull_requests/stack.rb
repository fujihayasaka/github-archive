# typed: true
# frozen_string_literal: true

module PullRequests
  class Stack < ApplicationRecord::Domain::IssuesPullRequests
    include ::Repositories::BelongsToRepository

    self.table_name = "pull_request_stacks"

    belongs_to_repository_via_domain
    has_many :entries, ->(s) { where(repository_id: s.repository_id).order(position: :asc) },
      class_name: "PullRequests::StackEntry",
      inverse_of: :stack,
      dependent: :destroy
    has_many :pull_requests, through: :entries

    sig { params(pulls: T::Array[PullRequest]).returns(Stack) }
    def self.create_with!(pulls)
      stack = new

      if pulls.size < 2
        raise ArgumentError, "Stack must contain at least two pull requests"
      end
      first_pull = T.must(pulls.first)
      repository = T.must(first_pull.repository)

      stack.repository = repository
      stack.base_ref = T.must(first_pull.base_ref)

      expected_base_ref = stack.base_ref
      pulls.each.with_index do |pull, index|
        if pull.base_ref != expected_base_ref
          raise ArgumentError, "Pull requests must form a stack, where each PR's base ref is the previous PR's head ref"
        end

        stack.entries.build(
          pull_request: pull,
          repository:,
          position: index + 1,
        )
        expected_base_ref = pull.head_ref
      end

      stack.save!
      stack
    end

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

    # The lowest-position entry whose pull request has not yet been merged.
    # This is the current "bottom" of the active stack — everything below it
    # has already landed on the base branch.
    sig { returns(T.nilable(PullRequests::StackEntry)) }
    def current_base_entry
      entries.order(position: :asc).find { |e| !e.pull_request&.merged? }
    end
  end
end
