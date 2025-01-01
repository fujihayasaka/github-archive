# typed: true
# frozen_string_literal: true

module TasklistBlocks
  class TasklistBlock
    DEFAULT_NAME = "Tasks"
    extend T::Sig

    TASKLIST_BLOCK_VALIDATION = "tasklist_blocks.validation"

    attr_accessor :name
    attr_accessor :name_html
    attr_accessor :validation_msg
    attr_accessor :items

    sig do
      params(
        name: T.nilable(String),
        name_html: T.nilable(String),
        items: T::Array[T.any(TasklistBlocks::IssueReference, TrackingBlocks::DraftIssue)],
        validation_msg: T.nilable(String)
      ).void
    end
    def initialize(name: DEFAULT_NAME, name_html: nil, items: [], validation_msg: nil)
      @name = name
      @name_html = name_html
      @items = items
      @validation_msg = validation_msg
    end

    sig { params(other: TasklistBlocks::TasklistBlock).returns(T::Boolean) }
    def ==(other)
      name == other.name &&
        items == other.items
    end

    # Convert the issue to a hash that can be used in the frontend
    # sig { returns(T::Hash[Symbol, T.untyped]) }
    sig do
      returns(
        {
          name: String,
          name_html: T.nilable(String),
          validation_msg: T.nilable(String),
          items: T::Array[T.any(TasklistBlocks::IssueReference, TrackingBlocks::DraftIssue)]
        },
      )
    end
    def to_h
      {
        name: name,
        name_html: name_html,
        items: items || [],
        validation_msg: validation_msg,
      }
    end
  end
end
