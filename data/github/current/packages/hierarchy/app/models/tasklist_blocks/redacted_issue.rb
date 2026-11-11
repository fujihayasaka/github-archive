# typed: true
# frozen_string_literal: true

module TasklistBlocks
  # rubocop:disable Naming/VariableName
  # rubocop:disable Naming/MethodName
  class RedactedIssue
    attr_reader :key,
                :title,
                :position,
                :state,
                :stateReason,
                :url,
                :number,
                :repoId,
                :repoName,
                :userName,
                :completion

    sig { params(position: Integer, title: String).void }
    def initialize(position:, title: "You can't see this item")
      @key = IssuesGraph::Proto::Key.new(
        ownerId: 0,
        itemId: 0,
        primaryKey: ::IssuesGraph::Proto::PrimaryKey.new(
          uuid: "00000000-0000-0000-0000-000000000000"
        )
      )
      @title = title
      @position = position
      @state = "draft"
      @stateReason = ""
      @url = ""
      @number = 0
      @repoId = 0
      @repoName = ""
      @userName = ""
      @assignees = []
      @labels = []
      @completion = nil
    end

    sig do
      returns(
        {
          uuid: T.nilable(String),
          item_id: T.nilable(Integer),
          title: String,
          state: String,
          url: String,
          state_reason: String,
          repository_name: String,
          display_number: Integer,
          owner_login: String,
          repository_id: Integer,
          assignees: T::Array[T.untyped],
          labels: T::Array[T.untyped],
          completion: T.nilable(TasklistBlocks::Completion),
          position: Integer,
        },
      )
    end
    def to_h
      {
        uuid: @key.primaryKey.uuid,
        item_id: @key.itemId,
        title: @title,
        state: @state,
        state_reason: @stateReason,
        url: @url,
        display_number: @number,
        repository_id: @repoId,
        repository_name: @repoName,
        owner_login: @userName,
        assignees: @assignees,
        labels: @labels,
        completion: @completion,
        position: @position,
      }
    end
  end
  # rubocop:enable Naming/MethodName
  # rubocop:enable Naming/VariableName
end
