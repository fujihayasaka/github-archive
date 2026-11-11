# typed: strict
# frozen_string_literal: true

module MemexProject::DefaultTemplates
  module Shared
    module Workflows
      WorkflowAction = T.type_alias do
        {
          action_type: String,
          arguments: T::Hash[T.any(String, Symbol), T.untyped]
        }
      end

      WorkflowDefinition = T.type_alias do
        {
          name: String,
          trigger_type: String,
          enabled: T::Boolean,
          content_types: T::Array[String],
          actions_attributes: T::Array[WorkflowAction]
        }
      end

      WORKFLOWS = T.let({
        item_closed: {
          name: "Item closed",
          trigger_type: "closed",
          enabled: true,
          content_types: %w[Issue PullRequest],
          actions_attributes: [
            {
              action_type: "set_field",
              arguments: {
                fieldName: "status",
                fieldOptionName: "Done"
              }
            }
          ]
        },
        pull_request_merged: {
          name: "Pull request merged",
          trigger_type: "merged",
          enabled: true,
          content_types: ["PullRequest"],
          actions_attributes: [
            {
              action_type: "set_field",
              arguments: {
                fieldName: "status",
                fieldOptionName: "Done"
              }
            }
          ]
        },
        auto_close_issue: {
          name: "Auto-close issue",
          trigger_type: "project_item_column_update",
          enabled: true,
          content_types: ["Issue"],
          actions_attributes: [
            {
              action_type: "get_project_items",
              arguments: {
                fieldName: "status",
                fieldOptionName: "Done"
              }
            },
            {
              action_type: "close_item",
              arguments: {}
            }
          ]
        },
        auto_add_sub_issues: {
          name: "Auto-add sub-issues to project",
          trigger_type: "sub_issues",
          enabled: true,
          content_types: ["Issue"],
          actions_attributes: [
            {
              action_type: "get_sub_issues",
              arguments: {}
            },
            {
              action_type: "add_project_item",
              arguments: {
                subIssue: true
              }
            }
          ]
        },
        item_added_to_triage: {
          name: "Item added to project",
          trigger_type: "item_added",
          enabled: true,
          content_types: %w[Issue PullRequest],
          actions_attributes: [
            {
              action_type: "set_field",
              arguments: {
                fieldName: "status",
                fieldOptionName: "To triage"
              }
            }
          ]
        },
        item_reopened_to_backlog: {
          name: "Item reopened",
          trigger_type: "reopened",
          enabled: true,
          content_types: %w[Issue PullRequest],
          actions_attributes: [
            {
              action_type: "set_field",
              arguments: {
                fieldName: "status",
                fieldOptionName: "Backlog"
              }
            }
          ]
        },
        pull_request_linked_to_issue: {
          name: "Pull request linked to issue",
          trigger_type: "pr_connected",
          enabled: true,
          content_types: ["Issue"],
          actions_attributes: [
            {
              action_type: "set_field",
              arguments: {
                fieldName: "status",
                fieldOptionName: "In progress",
              }
            }
          ]
        },
      }.freeze, T::Hash[Symbol, WorkflowDefinition])

      # Standard set of workflows used by most templates
      sig { returns(T::Array[WorkflowDefinition]) }
      def self.standard_workflows
        [
          T.must(WORKFLOWS[:item_closed]),
          T.must(WORKFLOWS[:pull_request_merged]),
          T.must(WORKFLOWS[:auto_close_issue]),
          T.must(WORKFLOWS[:auto_add_sub_issues]),
          T.must(WORKFLOWS[:pull_request_linked_to_issue]),
        ].freeze
      end

      # Parameterized workflow to set the status when an item is added to a project.
      # Templates can call this with a specific status option that exists on
      # the template's status column
      # @see: https://github.com/github/github/blob/main/packages/planning/app/models/memex_project/default_templates/feature_release_template.rb
      sig { params(status_to_set: String).returns(WorkflowDefinition) }
      def self.item_added_to_project_workflow(status_to_set)
        {
          name: "Item added to project",
          trigger_type: "item_added",
          enabled: true,
          content_types: %w[Issue PullRequest],
          actions_attributes: [
            {
              action_type: "set_field",
              arguments: {
                fieldName: "status",
                fieldOptionName: status_to_set
              }
            }
          ]
        }
      end

      # Shorthand method to get individual workflows with T.must safety
      sig { params(key: Symbol).returns(WorkflowDefinition) }
      def self.workflow(key)
        T.must(WORKFLOWS[key])
      end
    end
  end
end
