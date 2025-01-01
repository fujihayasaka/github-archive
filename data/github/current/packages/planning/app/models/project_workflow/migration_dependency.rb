# typed: false
# frozen_string_literal: true

module ProjectWorkflow::MigrationDependency
  extend ActiveSupport::Concern

  LEGACY_TRIGGER_TYPE_TO_BETA_TRIGGER_TYPE = {
    ProjectWorkflow::ISSUE_CLOSED_TRIGGER => :closed,
    ProjectWorkflow::PR_CLOSED_NOT_MERGED_TRIGGER => :closed,
    ProjectWorkflow::ISSUE_PENDING_CARD_ADDED_TRIGGER => :item_added,
    ProjectWorkflow::PR_PENDING_CARD_ADDED_TRIGGER => :item_added,
    ProjectWorkflow::ISSUE_REOPENED_TRIGGER => :reopened,
    ProjectWorkflow::PR_REOPENED_TRIGGER => :reopened,
    ProjectWorkflow::PR_PENDING_APPROVAL_TRIGGER => :review_changes_requested,
    ProjectWorkflow::PR_APPROVED_TRIGGER => :review_approved,
    ProjectWorkflow::PR_MERGED_TRIGGER => :merged,
  }

  def content_type
    trigger_type.include?("issue") ? MemexProjectItem::ContentType::Issue.serialize : MemexProjectItem::ContentType::PullRequest.serialize
  end

  class_methods do
    def to_memex_specification(legacy_workflows)
      legacy_workflows_by_beta_trigger_type = legacy_workflows.group_by do |w|
        LEGACY_TRIGGER_TYPE_TO_BETA_TRIGGER_TYPE[w.trigger_type]
      end

      legacy_workflows_by_beta_trigger_type.reduce([]) do |memo, (beta_trigger, legacy_workflows)|
        # Skip legacy workflows that don't have an equivalent trigger in the beta.
        next memo unless beta_trigger

        if legacy_workflows.uniq(&:project_column_id).length == 1
          # In this branch all legacy workflows target the same column, so we can combine
          # them into a single beta workflow with multiple content types.
          memo << workflow_data(
            beta_trigger,
            legacy_workflows.map(&:content_type),
            legacy_workflows.first.project_column_id.to_s
          )
        else
          # In this branch, each legacy workflow targets a different column, so we must
          # create one beta workflow for each legacy workflow.
          memo += legacy_workflows.map.with_index do |single_legacy_workflow, index|
            workflow_data(
              beta_trigger,
              [single_legacy_workflow.content_type],
              single_legacy_workflow.project_column_id.to_s,
              index
            )
          end
        end
      end
    end

    def workflow_data(beta_trigger, content_types, field_option_id, index = nil)
      {
        name: (index && index > 0) ? "#{MemexProjectWorkflow::DEFAULT_NAME_BY_TRIGGER_TYPE[beta_trigger]} (#{index})" : MemexProjectWorkflow::DEFAULT_NAME_BY_TRIGGER_TYPE[beta_trigger],
        enabled: true,
        trigger_type: beta_trigger.to_s,
        content_types: content_types,
        actions: [
          {
            type: "set_field",
            arguments: {
              field_id: Project::MigrationDependency::STATUS_FIELD_MIGRATION_ID,
              field_option_id: field_option_id,
            }
          }
        ]
      }
    end
  end
end
