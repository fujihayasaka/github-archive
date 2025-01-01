# typed: true
# frozen_string_literal: true

# View model converter for taking a Completion from the Issues graph api and convert it to a custom Ruby hash
module TasklistBlocks
  class Completion
    extend T::Sig

    attr_reader :uuid
    attr_reader :parent_issue
    attr_reader :completed
    attr_reader :total
    attr_reader :percent

    sig do
      params(
        completion: T.nilable(::IssuesGraph::Proto::Completion),
        parent_issue: T.nilable(TasklistBlocks::Issue)
      ).returns(T.nilable(TasklistBlocks::Completion))
    end
    def self.from_proto(completion:, parent_issue: nil)
      return nil unless completion
      new(
        parent_issue: parent_issue,
        uuid: completion.key&.primaryKey&.uuid,
        completed: completion.completed,
        total: completion.total,
        percent: completion.percent
      )
    end

    sig do
      params(
        uuid: T.nilable(String),
        completed: T.nilable(Integer),
        total: T.nilable(Integer),
        percent: T.nilable(Integer),
        parent_issue: T.nilable(TasklistBlocks::Issue)
      ).void
    end
    def initialize(
      uuid: nil,
      completed: nil,
      total: nil,
      percent: nil,
      parent_issue: nil
    )
      @uuid = uuid
      @completed = completed
      @total = total
      @percent = percent
      @parent_issue = parent_issue
    end


    sig { params(other: TasklistBlocks::Completion).returns(T::Boolean) }
    def ==(other)
      uuid == other.uuid &&
        completed == other.completed &&
        total == other.total &&
        percent == other.percent
    end

    sig do
      returns(
        {
          uuid: T.nilable(String),
          completed: T.nilable(Integer),
          total: T.nilable(Integer),
          percent: T.nilable(Integer),
        }
      )
    end
    def to_h
      {
        uuid: uuid,
        completed: completed,
        total: total,
        percent: percent
      }
    end
  end
end
