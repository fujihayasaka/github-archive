# typed: true
# frozen_string_literal: true

# Filters input items that match the configured query
#
# input - MemexProjectItem[] - the items to filter
#
# returns MemexProjectItem[] - the filtered items
class MemexProjectWorkflowAction::GetProjectItemsActionRunner < MemexProjectWorkflowAction::BaseActionRunner

  ACTION_TYPE = :get_project_items

  sig { returns(T::Array[MemexProjectItem]) }
  def run
    @query = @action.arguments["query"]
    @repository_id = @action.arguments["repositoryId"]
    @field_id = @action.arguments["fieldId"]
    @field_option_id = @action.arguments["fieldOptionId"]

    if @field_id.present? && @query.present?
      raise ArgumentError, "Cannot specify both a field and a query in a get_project_items action"
    end

    log_duration do
      if @manual_run
        raise ArgumentError, "manual run for get_project_items requires content_types" if @content_types.nil?
        get_items
      else
        filter_by_field? ? filter_items_by_field : filter_items_by_query
      end
    end
  end

  private

  sig { returns(T::Boolean) }
  def filter_by_field?
    @field_id.present? && @field_option_id.present?
  end

  sig { returns(T::Array[MemexProjectItem]) }
  def filter_items_by_query
    GitHub::PrefillAssociations.prefill_associations(@input, :content) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    MemexProjectWorkflowAction::ItemsFilter.filter_items(
      @input,
      @query,
      repository_id: @repository_id,
      memex_project_owner: memex_owner
    )
  end

  sig { returns(T::Array[MemexProjectItem]) }
  def filter_items_by_field
    GitHub::PrefillAssociations.prefill_associations(@input, :content) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    MemexProjectWorkflowAction::ItemsFilter.filter_items_by_field(@input, @field_id, @field_option_id)
  end

  sig { returns(T::Array[MemexProjectItem]) }
  def get_items
    result = []

    actual_content_types = @content_types.dup
    if actual_content_types.include?("Issue")
      actual_content_types.push("DraftIssue")
    end

    MemexProjectItem
    .preload(:content)
    .where(
      archived_at: nil,
      content_type: actual_content_types,
      memex_project: @action.workflow.memex_project
    )
    .in_batches(of: BATCH_SIZE) do |batch|
      filtered_items = if filter_by_field?
        MemexProjectWorkflowAction::ItemsFilter.filter_items_by_field(batch, @field_id, @field_option_id)
      else
        MemexProjectWorkflowAction::ItemsFilter.filter_items(
          batch,
          @query,
          repository_id: @repository_id,
          memex_project_owner: memex_owner
      )
      end
      result.push(*filtered_items)
    end

    result
  end

  sig { returns(T.any(User, Organization)) }
  def memex_owner
    @action.workflow.memex_project.owner
  end
end
