# typed: true
# frozen_string_literal: true

# Hierarchy is a non-ActiveRecord model that wraps the raw hierarchy data.
# Generally speaking, the purpose is to wrap data coming from the IssuesGraph
# service into Ruby objects.
class Hierarchy
  sig { returns(::IssuesGraph::Result) }
  attr_reader :raw_hierarchy

  sig do
    params(
      raw_hierarchy_result: ::IssuesGraph::Result
    ).void
  end
  def initialize(raw_hierarchy_result)
    @raw_hierarchy = raw_hierarchy_result
  end

  sig { returns(T::Array[TasklistBlock]) }
  def tasklist_blocks
    return [] unless raw_data&.tracking
    raw_data.tracking.map do |tracking|
      parent_issue = TasklistBlocks::Issue.from_proto(issue: raw_data.issue)
      TasklistBlock.new(
        parent_issue: parent_issue,
        key: TasklistBlocks::Key.from_proto(key: tracking.key),
        order: tracking.order,
        name: tracking.name,
        items: tracking.issues.map do |item|
          TasklistBlocks::Issue.from_proto(issue: item, parent_issue: parent_issue)
        end
      )
    end
  end

  sig { returns T.nilable(TasklistBlocks::Issue) }
  def issue
    return unless raw_data&.issue
    TasklistBlocks::Issue.from_proto(issue: raw_data&.issue)
  end

  sig { returns T.nilable(TasklistBlocks::Completion) }
  def completion
    return unless raw_data&.issue&.completion
    TasklistBlocks::Completion.from_proto(
      completion: raw_data.issue.completion,
      parent_issue: issue
    )
  end

  private

  def raw_data
    @raw_hierarchy.data
  end
end
