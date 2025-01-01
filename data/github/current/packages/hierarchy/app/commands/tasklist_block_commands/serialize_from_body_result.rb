# typed: true
# frozen_string_literal: true

module TasklistBlockCommands
  class SerializeFromBodyResult
    extend T::Sig

    sig do
      params(
        tasklists: T.any(
          TasklistBlocks::TasklistBlock,
          T::Array[TasklistBlocks::TasklistBlock]
        )
      ).void
    end
    def initialize(tasklists:)
      @tasklists = Array.wrap(tasklists)
    end

    sig { returns(TasklistBlockCommands::Result::SerializeFromBodyResult) }
    def call
      prefill_issue_associations

      TasklistBlockCommands::Result::SerializeFromBodyResult.new(
        success: true,
        data: serialize_tasklists
      )
    end

    private

    sig { void }
    def prefill_issue_associations
      GitHub::PrefillAssociations.prefill_associations(
        preloadables,
        [
          :assignees,
          :pull_request,
          :repository,
          labels: :repository,
        ]
      )
    end

    sig { returns(T::Array[TasklistBlocks::IssueReference]) }
    def preloadables
      @tasklists
        .flat_map(&:items)
        .reject(&:draft?)
        .map(&:issue)
    end

    sig { returns(T::Array[Hash]) }
    def serialize_tasklists
      @tasklists.map do |tasklist|
        {
          name: tasklist.name,
          issues: tasklist.items.map(&:to_hierarchy_model)
        }
      end
    end
  end
end
