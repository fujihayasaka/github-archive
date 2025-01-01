# typed: true
# frozen_string_literal: true

module SlashCommands
  class WorkflowCommand < ApplicationSlashCommand
    category :actions

    feature_flag :workflow_command

    def self.enabled?(context)
      super &&
        GitHub.actions_enabled? &&
        context.current_repository.actions_enabled? &&
        context.current_repository.writable_by?(context.current_user)
    end

    def self.triggers(context)
      description =
        case context.subject
        when PullRequest
          "Trigger GitHub Actions workflow for this pull request."
        when Issue
          "Trigger GitHub Actions workflow."
        end

      [
        Trigger.new(command: self, name: "workflow", title: "Run workflow", description: description)
      ]
    end

    allowed_surfaces :pull_request, :issue

    menu :list_of_workflows
    form :workflow_inputs_form, if: :workflow_inputs?
    perform_action :dispatch_workflow

    def list_of_workflows
      # TODO: This is limited to 25 because `has_workflow_dispatch_trigger?` parses the workflow file.
      #       Before staff shipping, let's make it possible to complete this filtering in the database.
      items = workflows.limit(25).select(&:has_workflow_dispatch_trigger?).map do |workflow|
        Item.from(text: workflow.name, value: workflow.path)
      end

      menu(
        :workflow_path,
        items: items,
        blankslate_title: "No workflows found",
        blankslate_description: "Be sure there are workflows in this repository that can be triggered by workflow_dispatch."
      )
    end

    def workflow_inputs_form
      fields = workflow_inputs.map do |name, config|
        UI.text_field(
          name,
          label: config[:description].presence || name.humanize,
          placeholder: "",
          required: config[:required],
          value: config[:default]
        )
      end

      form(*fields).with_actions(
        UI.submit_button("Run workflow")
      )
    end

    def workflow_inputs?
      workflow_valid_on_branch? && workflow_inputs.present?
    end

    def dispatch_workflow
      if workflow_valid_on_branch?
        processed_inputs = begin
          parsed_workflow.process_inputs(unprocessed_inputs)
        rescue ArgumentError => e
          flash.error = e.message
          return
        end

        current_repository.dispatch_workflow_event(current_user.id, workflow_path, branch, processed_inputs)
        flash.notice = "#{workflow.name} workflow run was successfully requested."
      else
        flash.error = "Workflow not found."
      end
    end

    private

    def workflow_valid_on_branch?
      return false unless workflow
      return false unless parsed_workflow
      return false unless parsed_workflow.has_workflow_dispatch_trigger?

      true
    end

    def unprocessed_inputs
      @unprocessed_inputs ||= begin
        if data.respond_to?(:permit!)
          data.permit!.to_h
        else
          data
        end
      end.except(:workflow_path).stringify_keys
    end

    def branch
      if context.subject.is_a?(PullRequest)
        context.subject.head_ref
      else
        current_repository.default_branch
      end
    end

    def workflow_path
      data[:workflow_path]
    end

    def workflow
      return @workflow if defined?(@workfow)

      @workflow = workflows.where(path: workflow_path)
        .limit(1)
        .to_a
        .find(&:has_workflow_dispatch_trigger?)
    end

    def workflow_inputs
      parsed_workflow&.workflow_dispatch_inputs
    end

    def workflows
      current_repository.workflows.active
    end

    def parsed_workflow
      @parsed_workflow ||= Actions::ParsedWorkflow.parse_from_yaml(current_repository, workflow_path, branch)
    end
  end
end
