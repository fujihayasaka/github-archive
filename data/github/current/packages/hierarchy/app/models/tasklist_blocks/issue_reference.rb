# typed: true
# frozen_string_literal: true

module TasklistBlocks
  class IssueReference
    attr_reader :issue
    attr_reader :uuid
    attr_reader :position
    attr_reader :parent_issue
    attr_reader :completion

    def initialize(issue:, uuid: nil, position: nil, completion: nil, parent_issue: nil)
      @issue = issue
      @uuid = uuid
      @position = position
      @completion = completion
      @parent_issue = parent_issue
    end

    def to_hierarchy_model
      model = if GitHub.flipper[:tasklist_block].enabled?(issue&.owner) && issue&.has_pull_request
        issue.pull_request.to_hierarchy_model
      else
        issue.to_hierarchy_model
      end
      model[:position] = position
      model[:key][:primaryKey] = IssuesGraph::Proto::PrimaryKey.new(uuid: @uuid) if @uuid
      model
    end

    # Public: Convert an issue to a TasklistBlocks::Issue mapping
    #
    # Returns TasklistBlocks::Issue.
    sig { returns(TasklistBlocks::Issue) }
    def to_tasklist_issue
      owner_login, repository_name, _ = issue.repository.name_with_display_owner.split("/")

      TasklistBlocks::Issue.new(
        uuid: uuid,
        position: position,
        completion: completion,
        issue_id: issue.id,
        title: issue.title,
        state: issue.state,
        url: issue.url,
        number: issue.number,
        repository_id: issue.repository_id,
        repository_name: repository_name,
        owner_id: issue.repository.owner_id,
        owner_display_login: owner_login,
        parent_issue: parent_issue,
      )
    end

    def ==(other)
      issue == other.issue
    end

    sig { returns(T::Boolean) }
    def draft?
      false
    end
  end
end
