# typed: true
# frozen_string_literal: true
#
# This class is used to apply a "set field" action change to a given set of project item columns
class MemexProjectWorkflow::SetFieldProcessor

  include MemexProjectWorkflow::WorkflowQueries
  include MemexHydroProjectAutomation::Instrumentation::SetFieldProcessor

  BATCH_SIZE = 10

  sig do
    params(
      input: T::Array[MemexProjectItem],
      trigger_type: T.any(String, Symbol),
      action: MemexProjectWorkflowAction,
      actor: User,
      tags: T.nilable(T::Array[String])
    ).returns(T::Array[MemexProjectItem])
  end
  def self.run(input:, trigger_type:, action:, actor:, tags: [])
    new(input: input, trigger_type: trigger_type, action: action, actor: actor, tags: tags).run
  end

  sig do
    params(
      input: T::Array[MemexProjectItem],
      trigger_type: T.any(String, Symbol),
      action: MemexProjectWorkflowAction,
      actor: User,
      tags: T.nilable(T::Array[String])
    ).void
  end
  def initialize(input:, trigger_type:, action:, actor:, tags: [])
    @input = input
    @trigger_type = trigger_type.to_sym
    @action = action
    @actor = actor
    @tags = tags || []
  end

  # Execute the `set_field` action type for a given collection of project items
  # Returns an array of project items that were successfully updated
  sig { returns(T::Array[MemexProjectItem]) }
  def run
    updated_items = T.let([], T::Array[MemexProjectItem])
    target_column = MemexProjectColumn.find_by(id: @action["arguments"]["fieldId"])&.to_field&.tap do |field|
      next unless field
      GitHub::PrefillAssociations.prefill_associations([field], :memex_project)
    end

    return updated_items unless target_column.present?

    # Slice up the project items into batches for the sake of throttling.
    @input.each_slice(BATCH_SIZE) do |project_items|
      GitHub::PrefillAssociations.prefill_associations(project_items, :memex_project_column_values)
      with_write_values do
        project_items.each do |project_item|
          field_option_id = @action["arguments"]["fieldOptionId"]

          # A user can potentially add an item with an initial field value if they're adding from the board or a grouped by view
          # In these scenarios, we're making the assumption that the user wants to preserve that field value,
          # instead of potentially overwriting it with the value in the `set_field` action's arguments.
          #
          # A more generic solution here could be something around conditions, where we pass the item,
          # trigger_type, and action into a function which provides a yes/no as to whether or not to move
          # forward with executing the action. However, given we don't really know how this concept is going to
          # develop, we're keeping this simple for now.
          if @trigger_type == :item_added
            existing_column_value = target_column.memex_project_column_values.find_by(memex_project_item: project_item)
            if existing_column_value.present?
              existing_column_value_payload = log_payload(
                project_item,
                @action,
                target_column,
                reason: REASON_COLUMN_VALUE_EXISTS
              )
              log_action_skipped(**existing_column_value_payload)
              next
            end
          end

          # If this was triggered by review_approved, and the item is a PullRequest - skip if the PR is not fully approved
          if @trigger_type == :review_approved && project_item.pull_request? && !project_item.content.approved_with_no_changes_requested?
            not_fully_approved_payload = log_payload(
              project_item,
              @action,
              target_column,
              reason: REASON_REVIEWS_NOT_FULLFILED
            )
            log_action_skipped(**not_fully_approved_payload)
            next
          end

          # If this was triggered by review_approved, and the item is a PullRequest - skip if the PR has already been merged.
          # This can result from a race condition between :review_approved and :merged when using PR auto-merge.
          # We don't want to revert the project item's Status out of a typical 'Done' state.
          if @trigger_type == :review_approved && project_item.pull_request? && project_item.content.merged?
            pull_request_merged_payload = log_payload(
              project_item,
              @action,
              target_column,
              reason: REASON_PULL_REQUEST_MERGED
            )
            log_action_skipped(**pull_request_merged_payload)
            next
          end

          # column value updates are instrumented to rely on the request context
          # we are not in a request context here so provide the actor_id manually to the global context
          GitHub.context.push({ actor_id: Apps::Privileged::MemexAutomation.bot.id }) do
            value_update_success = project_item.set_column_value(target_column, field_option_id, Apps::Privileged::MemexAutomation.bot, skip_elasticsearch_updates: false)
            updated_items << project_item if value_update_success

            set_field_payload = log_payload(
              project_item,
              @action,
              target_column,
              result: value_update_success ? "success" : "failure"
            )
            log_set_field(**set_field_payload)
          end
        end
      end
    end

    updated_items
  end
end
