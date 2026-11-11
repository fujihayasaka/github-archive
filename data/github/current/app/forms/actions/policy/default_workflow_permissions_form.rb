# typed: true
# frozen_string_literal: true

module Actions
  module Policy
    class DefaultWorkflowPermissionsForm < ApplicationForm
      form do |workflow_perms_form|
        workflow_perms_form.radio_button_group(name: "actions_default_workflow_permissions") do |workflow_perms_group|
          workflow_perms_group.radio_button(
            value: "write",
            label: "Read and write permissions",
            caption: "Workflows have read and write permissions in the repository for all scopes.",
            checked: !@entity.actions_default_workflow_permissions_read_only?,
            disabled: !@entity.actions_can_have_default_workflow_permissions_read_write?
          )

          workflow_perms_group.radio_button(
            value: "read",
            label: "Read repository contents and packages permissions",
            caption: "Workflows have read permissions in the repository for the contents and packages scopes only.",
            checked: @entity.actions_default_workflow_permissions_read_only?
          )
        end

        workflow_perms_form.check_box_group(
          label: "Choose whether GitHub Actions can create pull requests or submit approving pull request reviews.",
          label_arguments: {
            style: "font-weight:normal"
          }) do |check_group|
          check_group.check_box(
            name: "actions_workflow_permission_can_approve_pr",
            label: "Allow GitHub Actions to create and approve pull requests",
            class: "form-checkbox-details-trigger",
            checked: @entity.actions_workflow_permission_can_approve_pr?,
            disabled: !@entity.actions_workflow_permission_can_allow_pr_approval?
          )
        end

        workflow_perms_form.submit(
          name: :submit,
          label: "Save",
          aria: {
            label: "Save workflow permissions settings"
          }
        )
      end

      def initialize(entity:)
        @entity = entity
      end
    end
  end
end
