# typed: true
# frozen_string_literal: true

class HydroMemexBulkAddAutomationJob < MemexHydroProjectAutomation::HydroBasePipedProjectAutomationJob

  queue_as :hydro_memex_bulk_add_automation

  def perform
    return unless FeatureFlag.vexi.enabled?(:bulk_add_automation_hydro, default: false)

    log_topic
    return skip_automations_disabled unless GitHub.projects_automation_enabled?

    memex_project_id, memex_project_item_ids, actor_id = message_content(message)
    actor = User.new(id: actor_id)
    enqueue_workflows_for_bulk_add_project_items(memex_project_item_ids, :set_field, actor, :item_added)
  end

  def project_item_processable?(_project_item)
    true
  end

  sig { params(project_item_ids: T::Array[Integer], target_action: Symbol, actor: User, trigger_type: T.nilable(Symbol)).void }
  private def enqueue_workflows_for_bulk_add_project_items(project_item_ids, target_action, actor, trigger_type = nil)
    found_any_project_items = T.let(false, T::Boolean)
    found_any_workflows = T.let(false, T::Boolean)
    issue_item_ids = T.let([], T::Array[MemexProjectItem])

    run_all_workflows_enabled = FeatureFlag.vexi.enabled?(:memex_additional_workflows_by_trigger, actor, default: false)

    if run_all_workflows_enabled
      select_project_items(project_item_ids) do |project_items|
        trigger_action_pairs_by_item = evaluate_workflows_for_added_items(project_items, actor)
        trigger_action_pairs_by_item.each do |project_item, trigger_action_pairs|
          trigger_action_pairs.each do |trigger_type, action_type|
            seen_items, seen_workflows = enqueue_workflows_for_project_items([project_item], action_type, actor, trigger_type)
            found_any_project_items = true if seen_items.any?
            found_any_workflows = true if seen_workflows.any?
          end
        end
      end
    else
      select_project_items(project_item_ids) do |project_items|
        seen_items, seen_workflows = enqueue_workflows_for_project_items(project_items, target_action, actor, trigger_type)

        issue_items = project_items.select { |item| item.content_type == "Issue" && item.issue_id.present? }

        if issue_items.any?
          issue_item_ids.concat(issue_items)
        end

        found_any_project_items = true if seen_items.any?
        found_any_workflows = true if seen_workflows.any?
      end

      if issue_item_ids.any?
        issue_ids = issue_item_ids.map(&:issue_id).compact.uniq
        select_issue_ids_with_sub_issues(issue_ids) do |issue_ids_with_sub_issues|
          project_items_with_sub_issues = issue_item_ids.select { |item| issue_ids_with_sub_issues.include?(item.issue_id) }
          enqueue_workflows_for_project_items(project_items_with_sub_issues, :add_project_item, actor, :sub_issues) if project_items_with_sub_issues.any?
        end
      end
    end

    return skip_no_matches if !found_any_project_items
    return skip_no_workflows if !found_any_workflows

    log_success
  end

  private def get_input(project_item, trigger_type = nil, sub_issue_id = nil)
    return super unless trigger_type == :sub_issues

    sub_issues = project_item.content.try(:sub_issues) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    filtered_sub_issues = if initial_import?
      sub_issues.filter(&:open?) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    else
      sub_issues
    end
    filtered_sub_issues.try(:map) { |sub_issue| [MemexProjectItem::ContentType::Issue.serialize, sub_issue.id] } || []  # domain-isolation-query-violation:ignore:packages/issues (SELECT)
  end

  private def initial_import?
    message.dig(:initial_import) == true
  end

  private def message_content(message)
    memex_project_id = message.dig(:memex_project, :id)
    memex_project_item_ids = message.dig(:memex_project_item_ids)
    actor_id = message.dig(:actor, :id)

    [memex_project_id, memex_project_item_ids, actor_id]
  end
end
