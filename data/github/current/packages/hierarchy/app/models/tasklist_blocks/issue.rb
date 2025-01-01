# typed: true
# frozen_string_literal: true

#View model converter for taking an issue from the Issues graph api and convert it to a custom Ruby hash
module TasklistBlocks
  # TasklistBlocks::Issue can be used as a common interface between TasklistBlocks::DraftIssue,
  # IssuesGraph::Proto::Issue and TasklistBlocks::IssueReference models.
  class Issue
    attr_reader :uuid
    attr_reader :issue_id
    attr_reader :title
    attr_reader :state
    attr_reader :state_reason
    attr_reader :url
    attr_reader :number
    attr_reader :repository_id
    attr_reader :repository_name
    attr_reader :owner_id
    attr_reader :owner_display_login
    attr_reader :assignees
    attr_reader :labels
    attr_reader :position
    attr_accessor :completion
    attr_reader :parent_issue
    attr_accessor :title_html
    attr_accessor :item_type
    attr_accessor :tracked_by_title
    attr_accessor :original_text
    attr_accessor :timestamp

    sig do
      params(
        issue: ::IssuesGraph::Proto::Issue,
        parent_issue: T.nilable(TasklistBlocks::Issue)
      ).returns(TasklistBlocks::Issue)
    end
    def self.from_proto(issue:, parent_issue: nil)
      new(
        title: issue.title,
        state: issue.state,
        uuid: issue.key&.primaryKey&.uuid,
        issue_id: issue.key&.itemId,
        state_reason: issue.stateReason,
        url: issue.url,
        number: issue.number,
        repository_id: issue.repoId,
        repository_name: issue.repoName,
        owner_id: issue.key&.ownerId,
        owner_display_login: issue.userName,
        assignees: issue.assignees,
        labels: issue.labels,
        position: issue.position,
        title_html: nil,
        parent_issue: parent_issue,
        item_type: issue.itemType,
        original_text: nil,
        timestamp: issue.timestamp,
      ).tap do |block_issue|
        # Need the object defined before we can use it as a parent reference
        block_issue.completion = TasklistBlocks::Completion.from_proto(
          completion: issue.completion,
          parent_issue: block_issue
        )
      end
    end

    sig { params(tracking_block: ::IssuesGraph::Proto::TrackingBlock).returns(TasklistBlocks::Issue) }
    def self.from_tracking_block_proto(tracking_block:)
      issue = tracking_block.issues.first
      self.from_proto(issue: issue).tap do |block_issue|
        block_issue.tracked_by_title = tracking_block.name
      end
    end

    sig do
      params(
        title: String,
        state: String,
        uuid: T.nilable(String),
        issue_id: T.nilable(Integer),
        state_reason: T.nilable(String),
        url: T.nilable(String),
        number: T.nilable(Integer),
        repository_id: T.nilable(Integer),
        repository_name: T.nilable(String),
        owner_id: T.nilable(Integer),
        owner_display_login: T.nilable(String),
        assignees: T.untyped,
        labels: T.untyped,
        position: T.nilable(Integer),
        completion: T.nilable(TasklistBlocks::Completion),
        title_html: T.nilable(String),
        parent_issue: T.nilable(TasklistBlocks::Issue),
        item_type: T.nilable(T.any(Symbol, Integer)),
        tracked_by_title: T.nilable(String),
        original_text: T.nilable(String),
        timestamp: T.nilable(Integer),
      ).void
    end
    def initialize(
      title:,
      state:,
      uuid: nil,
      issue_id: nil,
      state_reason: nil,
      url: nil,
      number: nil,
      repository_id: nil,
      repository_name: nil,
      owner_id: nil,
      owner_display_login: nil,
      assignees: [],
      labels: [],
      position: nil,
      completion: nil,
      title_html: nil,
      parent_issue: nil,
      item_type: nil,
      tracked_by_title: nil,
      original_text: nil,
      timestamp: nil
    )
      @title = title
      @state = state
      @uuid = uuid
      @issue_id = issue_id
      @state_reason = state_reason
      @url = url
      @number = number
      @repository_id = repository_id
      @repository_name = repository_name
      @owner_id = owner_id
      @owner_display_login = owner_display_login
      @assignees = assignees
      @labels = labels
      @position = position
      @completion = completion
      @title_html = title_html
      @parent_issue = parent_issue
      @item_type = item_type
      @tracked_by_title = tracked_by_title
      @original_text = original_text
      @timestamp = timestamp
    end

    sig { params(other: TasklistBlocks::Issue).returns(T::Boolean) }
    def ==(other)
      title == other.title &&
        state == other.state &&
        uuid == other.uuid &&
        issue_id == other.issue_id &&
        state_reason == other.state_reason &&
        url == other.url &&
        number == other.number &&
        repository_id == other.repository_id &&
        repository_name == other.repository_name &&
        owner_id == other.owner_id &&
        owner_display_login == other.owner_display_login &&
        assignees == other.assignees &&
        labels == other.labels &&
        position == other.position &&
        completion == other.completion &&
        item_type == other.item_type
    end

    sig { returns(T::Boolean) }
    def draft?
      [TasklistBlocks::DraftIssueState::OPEN, TasklistBlocks::DraftIssueState::CLOSED].include?(state)
    end

    sig { returns(T::Boolean) }
    def closed?
      [TasklistBlocks::IssueState::CLOSED, TasklistBlocks::DraftIssueState::CLOSED, TasklistBlocks::PullRequestState::MERGED].include?(state)
    end

    sig { returns(T.nilable(::Issue::Authorizable)) }
    def to_authorizable
      return unless issue_id && repository_id

      ::Issue::Authorizable.new(issue_id, repository_id)
    end

    # Convert the issue to a hash that can be used in the frontend
    # sig { returns(T::Hash[Symbol, T.untyped]) }
    sig do
      returns(
        {
          uuid: T.nilable(String),
          item_id: T.nilable(Integer),
          title: String,
          state: String,
          url: T.nilable(String),
          state_reason: T.nilable(String),
          repository_name: T.nilable(String),
          display_number: T.nilable(Integer),
          owner_login: T.nilable(String),
          repository_id: T.nilable(Integer),
          assignees: T.untyped,
          labels: T.untyped,
          position: T.nilable(Integer),
          completion: T.nilable(Hash),
          title_html: T.nilable(String),
          item_type: T.nilable(T.any(Symbol, Integer)),
          tracked_by_title: T.nilable(String),
        },
      )
    end
    def to_h
      {
        uuid: uuid,
        item_id: issue_id,
        title: title,
        state: state,
        state_reason: state_reason,
        url: url,
        display_number: number,
        repository_id: repository_id,
        repository_name: repository_name,
        owner_login: owner_display_login,
        assignees: assignees,
        labels: labels,
        position: position,
        completion: completion&.to_h,
        title_html: title_html,
        item_type:  item_type,
        tracked_by_title: tracked_by_title,
      }
    end

    sig do
      returns(
        {
          key: {
            ownerId: T.nilable(Integer),
            itemId: T.nilable(Integer),
            primaryKey: T.nilable({ uuid: T.nilable(String) }),
          },
          title: String,
          url: T.nilable(String),
          state: String,
          repoName: T.nilable(String),
          repoId: T.nilable(Integer),
          userName: T.nilable(String),
          stateReason: T.nilable(String),
          number: T.nilable(Integer),
          assignees: T.untyped,
          labels: T.untyped,
          position: T.nilable(Integer),
          itemType: T.nilable(T.any(Symbol, Integer)),
        },
      )
    end
    def to_tracked_by_item
      {
        key: {
          ownerId: owner_id,
          itemId: issue_id,
          primaryKey: uuid ? { uuid: uuid } : nil
        },
        title: title,
        url: url,
        state: state,
        repoName: repository_name,
        repoId: repository_id,
        userName: owner_display_login,
        number: number,
        labels: labels,
        assignees: assignees,
        stateReason: state_reason,
        position: position,
        itemType: item_type,
      }
    end

    class IssueLink < T::Struct
      prop :issue_id, Integer
      prop :issue_number, Integer
      prop :issue_state, String
      prop :issue_state_reason, T.nilable(String)
      prop :issue_title, String
      prop :issue_url, String
      prop :owner, String
      prop :repository, String
      prop :tracked_by_title, T.nilable(String)
    end

    # Public: Convert the issue to a hash that can be used in IssueLink
    # dependency.
    #
    # Returns a hash.
    sig do
      returns(IssueLink)
    end
    def to_issue_link
      IssueLink.new(
        issue_id: issue_id,
        issue_number: number,
        issue_state: state,
        issue_state_reason: state_reason,
        issue_title: title,
        issue_url: url,
        owner: owner_display_login,
        repository: repository_name,
        tracked_by_title: tracked_by_title,
      )
    end
  end
end
