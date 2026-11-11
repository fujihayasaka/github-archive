# typed: true
# frozen_string_literal: true

class HydroMemexBulkAddAutomationJob < MemexHydroProjectAutomation::HydroBasePipedProjectAutomationJob

  queue_as :hydro_memex_bulk_add_automation

  def perform
    log_topic
    return skip_automations_disabled unless GitHub.projects_automation_enabled?

    memex_project_id, memex_project_item_ids, actor_id = message_content(message)
    actor = T.let(User.new(id: actor_id), User)
    @actor = T.let(actor, T.nilable(User))

    if defer_sub_issues_workflow?
      if import_complete?
        enqueue_import_complete_workflows(memex_project_item_ids, actor)
      else
        enqueue_workflows_for_bulk_add_project_items(memex_project_item_ids, :set_field, actor, :item_added)
      end
    else
      enqueue_workflows_for_bulk_add_project_items(memex_project_item_ids, :set_field, actor, :item_added)
    end
  end

  def project_item_processable?(_project_item)
    true
  end

  sig { params(project_item_ids: T::Array[Integer], target_action: Symbol, actor: User, trigger_type: T.nilable(Symbol)).void }
  private def enqueue_workflows_for_bulk_add_project_items(project_item_ids, target_action, actor, trigger_type = nil)
    found_any_project_items = T.let(false, T::Boolean)
    found_any_workflows = T.let(false, T::Boolean)

    excluded = defer_sub_issues_workflow? ? [:sub_issues] : []
    select_project_items(project_item_ids) do |project_items|
      trigger_action_pairs_by_item = evaluate_workflows_for_added_items(project_items, actor, exclude_triggers: excluded)
      trigger_action_pairs_by_item.each do |project_item, trigger_action_pairs|
        trigger_action_pairs.each do |trigger_type, action_type|
          seen_items, seen_workflows = enqueue_workflows_for_project_items([project_item], action_type, actor, trigger_type)
          found_any_project_items = true if seen_items.any?
          found_any_workflows = true if seen_workflows.any?
        end
      end
    end

    finalize_workflow_results(found_any_project_items, found_any_workflows)
  end

  sig { params(project_item_ids: T::Array[Integer], actor: User).void }
  private def enqueue_import_complete_workflows(project_item_ids, actor)
    found_any_project_items = T.let(false, T::Boolean)
    found_any_workflows = T.let(false, T::Boolean)

    select_project_items(project_item_ids) do |project_items|
      project_items_with_sub_issues = select_project_items_with_sub_issues(project_items)
      next if project_items_with_sub_issues.empty?

      seen_items, seen_workflows = enqueue_workflows_for_project_items(
        project_items_with_sub_issues, :add_project_item, actor, :sub_issues
      )
      found_any_project_items |= seen_items.any?
      found_any_workflows |= seen_workflows.any?
    end

    finalize_workflow_results(found_any_project_items, found_any_workflows)
  end

  sig do
    override.params(
      project_item: MemexProjectItem,
      trigger_type: T.nilable(Symbol),
      sub_issue_id: T.nilable(Integer)
    ).returns(T::Array[[String, Integer]])
  end

  private def get_input(project_item, trigger_type = nil, sub_issue_id = nil)
    return super unless trigger_type == :sub_issues

    open_sub_issues = project_item.content.try(:sub_issues)&.select do |sub_issue| # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      sub_issue.state == "open"
    end

    sub_issue_inputs = open_sub_issues&.map do |sub_issue|
      [MemexProjectItem::ContentType::Issue.serialize, sub_issue.id]
    end

    sub_issue_inputs || []
  end

  sig { returns(T::Boolean) }
  private def import_complete?
    message.dig(:import_complete) == true
  end

  sig { returns(T::Boolean) }
  private def initial_import?
    message.dig(:initial_import) == true
  end

  sig { returns(T::Boolean) }
  private def defer_sub_issues_workflow?
    FeatureFlag.vexi.enabled?(:memex_defer_auto_add_workflow_on_bulk_import, T.must(@actor), default: false)
  end

  sig { params(found_any_project_items: T::Boolean, found_any_workflows: T::Boolean).void }
  private def finalize_workflow_results(found_any_project_items, found_any_workflows)
    return skip_no_matches unless found_any_project_items
    return skip_no_workflows unless found_any_workflows

    log_success
  end

  private def message_content(message)
    memex_project_id = message.dig(:memex_project, :id)
    memex_project_item_ids = message.dig(:memex_project_item_ids)
    actor_id = message.dig(:actor, :id)

    [memex_project_id, memex_project_item_ids, actor_id]
  end
end
