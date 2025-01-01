# typed: true
# frozen_string_literal: true

module TrackingBlocks
  class DraftIssue
    extend T::Sig

    attr_reader :draft_issue
    attr_reader :owner_id
    attr_reader :uuid
    attr_reader :closed
    attr_reader :position
    attr_accessor :title_html
    attr_reader :parent_issue

    ITEM_TYPE = "DRAFT_ISSUE"

    # draft_issue: - String
    # owner_id: - Integer
    # uuid: - String
    # closed: - Boolean
    # position: - Integer
    def initialize(draft_issue:, owner_id:, uuid: nil, closed: false, position: 0, title_html: nil, parent_issue: nil)
      @draft_issue = draft_issue
      @owner_id = owner_id
      @uuid = uuid
      @closed = closed
      @position = position
      @title_html = title_html
      @parent_issue = parent_issue
    end

    def ==(other)
      return false unless other.is_a?(DraftIssue)

      draft_issue == other.draft_issue &&
        owner_id == other.owner_id &&
        uuid == other.uuid &&
        closed == other.closed &&
        position == other.position &&
        title_html == other.title_html
    end

    # Public: Convert an issue to a TasklistBlocks::Issue mapping
    #
    # Returns TasklistBlocks::Issue.
    def to_tasklist_issue
      TasklistBlocks::Issue.new(
        uuid: uuid,
        title: draft_issue,
        state: closed ? TasklistBlocks::DraftIssueState::CLOSED : TasklistBlocks::DraftIssueState::OPEN,
        owner_id: owner_id,
        position: position,
        title_html: title_html,
        parent_issue: parent_issue
      )
    end

    def to_hierarchy_model
      model = {
        key: {
          ownerId: owner_id,
        },
        title: draft_issue,
        state: closed ? TasklistBlocks::DraftIssueState::CLOSED : TasklistBlocks::DraftIssueState::OPEN,
        position: position,
        itemType: ITEM_TYPE,
      }
      model[:key][:primaryKey] = IssuesGraph::Proto::PrimaryKey.new(uuid: uuid) if uuid
      model
    end

    sig { returns(T::Boolean) }
    def draft?
      true
    end
  end
end
