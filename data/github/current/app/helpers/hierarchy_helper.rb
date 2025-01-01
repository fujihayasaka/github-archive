# typed: true
# frozen_string_literal: true

module HierarchyHelper
  include Kernel
  extend T::Sig

  POSITION_GAP_SIZE = 100

  sig { params(parent: Issue, tracking_blocks: T::Array[T.untyped]).returns(T.untyped) }
  def add_tracking_blocks_for_parent(parent:, tracking_blocks:)
    client = GitHub.issues_graph_api_client

    model = parent.to_hierarchy_model
    raise ::IssuesGraph::Errors::ClientError unless model.present?

    result = client.add_tracking_block_for_parent(
      model,
      tracking_blocks,
      stat_tags: ["context:hierarchy_helper"]
    )
    raise ::IssuesGraph::Errors::ClientError if result.error?

    result.data.primaryKeys
  end

  def remove_tracking_blocks_for_parent(parent:, tracking_block_ids:)
    owner_id = parent.owner.id
    item_id = parent.id
    client = GitHub.issues_graph_api_client

    # TODO: a bulk-delete API would be handy on the issues-graph side
    responses = []
    tracking_block_ids.each do |tracking_block_id|
      result = client.remove_tracking_block(owner_id, item_id, tracking_block_id, stat_tags: ["context:hierarchy_helper"])
      raise ::IssuesGraph::Errors::ClientError if result.error?

      responses.push(result)
    end
    responses
  end

  sig do
    params(
      owner_id: Integer,
      block_id: String,
      issues_to_add: T::Array[Issue],
      issues_to_remove: T::Array[TrackingBlocks::KeyOnlyItem],
    ).returns(T.untyped)
  end
  def update_tracking_block_by_key(owner_id:, block_id:, issues_to_add: [], issues_to_remove: [])
    block_key = IssuesGraph::Proto::Key.new(ownerId: owner_id, primaryKey: IssuesGraph::Proto::PrimaryKey.new(uuid: block_id))
    result = GitHub.issues_graph_api_client.update_tracking_block_by_key(
      block_key,
      issues_to_add.map(&:to_hierarchy_model).compact,
      issues_to_remove.map(&:to_hierarchy_model),
      stat_tags: ["context:hierarchy_helper"]
    )

    result.data
  end

  def update_tracking_block_in_place_by_key(owner_id:, block_id:, issues_to_update: [])
    block_key = IssuesGraph::Proto::Key.new(ownerId: owner_id, primaryKey: IssuesGraph::Proto::PrimaryKey.new(uuid: block_id))
    result = GitHub.issues_graph_api_client.update_tracking_block_in_place_by_key(
      block_key,
      issues_to_update.map(&:to_hierarchy_model),
      stat_tags: ["context:hierarchy_helper"]
    )

    result.data
  end

  def instrument_tasklist_block_operation(operation:, actor:, repository:, issue:)
    case operation
    when TasklistBlocks::Operations::AppendItem
      instrument_tasklist_block_item_add(actor: actor, repository: repository, issue: issue, item_type: get_item_type_from_operation(operation))
    when TasklistBlocks::Operations::RemoveItem
      instrument_tasklist_block_item_remove(actor: actor, repository: repository, issue: issue)
    when TasklistBlocks::Operations::ConvertToIssue
      instrument_tasklist_block_item_convert(actor: actor, repository: repository, issue: issue)
    when TasklistBlocks::Operations::UpdateTasklistTitle
      instrument_tasklist_block_rename(actor: actor, repository: repository, issue: issue)
    end
  end

  def instrument_tasklist_block_md_to_ui_operation(operations:, actor:, repository:, issue:)
    # convert to issue is not tracked because it is currently handled server side as part of the instrument_tasklist_block_operation method
    operations.each do |operation|
      case operation["name"]
      when "append_item"
        instrument_tasklist_block_item_add(actor: actor, repository: repository, issue: issue, item_type: get_item_type_from_operation(operation))
      when "remove_item"
        instrument_tasklist_block_item_remove(actor: actor, repository: repository, issue: issue)
      when "update_tasklist_title"
        instrument_tasklist_block_rename(actor: actor, repository: repository, issue: issue)
      else
        nil
      end
    end
  end

  def instrument_tasklist_block_add(actor:, repository:, issue:)
    GlobalInstrumenter.instrument("tasklist.add", {
      actor: actor,
      issue_repository: repository,
      issue: issue,
    })
  end

  def instrument_tasklist_block_item_add(actor:, repository:, issue:, item_type: nil)
    GlobalInstrumenter.instrument("tasklist.item.add", {
      actor: actor,
      issue_repository: repository,
      issue: issue,
      item_type: item_type,
    })
  end

  def instrument_tasklist_block_item_remove(actor:, repository:, issue:, item_type: nil)
    GlobalInstrumenter.instrument("tasklist.item.remove", {
      actor: actor,
      issue_repository: repository,
      issue: issue,
      item_type: item_type,
    })
  end

  def instrument_tasklist_block_item_convert(actor:, repository:, issue:, draft_title: nil, created_issue_id: nil)
    GlobalInstrumenter.instrument("tasklist.item.convert", {
      actor: actor,
      issue_repository: repository,
      issue: issue,
      draft_title: draft_title,
      created_issue_id: created_issue_id,
      source: :TASKLIST_BLOCK,
    })
  end

  def instrument_tasklist_block_rename(actor:, repository:, issue:)
    GlobalInstrumenter.instrument("tasklist.rename", {
      actor: actor,
      issue_repository: repository,
      issue: issue,
    })
  end

  sig { params(operation: T.nilable(T.any(TasklistBlocks::Operations::AppendItem, T::Hash[String, String]))).returns(Symbol) }
  def get_item_type_from_operation(operation)
    return :UNKOWN unless operation

    case operation
    when TasklistBlocks::Operations::AppendItem
      parsed_value = operation.value
    when Hash
      parsed_value = operation["value"]
    end

    return :DRAFT unless parsed_value.start_with?(GitHub.url) || parsed_value.match?(GitHub::IssueReferenceParser::ISSUE_REFERENCE)

    case parsed_value
    when /\/pull\/\d+/ then :PULL_REQUEST
    when /\/issues\/\d+/ then :ISSUE
    else
      :UNKNOWN
    end
  end

  def instrument_tasklist_block_item_metadata_menu_click(actor:, parent_repository:, parent_issue:, child_issue:, menu_type: nil)
    menu_type_symbol = :UNKNOWN

    if menu_type == "labels"
      menu_type_symbol = :LABELS
    elsif menu_type == "assignees"
      menu_type_symbol = :ASSIGNEES
    elsif menu_type == "project"
      menu_type_symbol = :PROJECT
    end

    GlobalInstrumenter.instrument("tasklist.item.metadata_menu_click", {
      actor: actor,
      parent_repository: parent_repository,
      parent_issue: parent_issue,
      child_issue: child_issue,
      menu_type: menu_type_symbol,
    })
  end
end
