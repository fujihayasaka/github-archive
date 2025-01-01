# typed: false
# frozen_string_literal: true

module Configurable
  module DefaultWorkflowPermissions
    KEY = "actions_default_workflow_permissions"
    ALLOWED_VALUES = ["read"].freeze
    # Adding configuration value for https://github.com/github/c2c-actions-policy/issues/215
    # yes = true; no = false
    # do not rename the KEY value without a data migration
    KEY_PR_APPROVAL_COUNTS = "actions_workflow_permission_pr_approval_counts"
    ALLOWED_VALUES_PR_APPROVAL_COUNTS = [true, false].freeze

    Error = Class.new(StandardError)

    # Getter/Setters for actions_default_workflow_permissions
    def actions_default_workflow_permissions
      config.get(KEY)
    end

    def actions_default_workflow_permissions_read_only?
      config.get(KEY) == "read"
    end

    def actions_can_have_default_workflow_permissions_read_write?
      !config.inherited?(KEY)
    end

    def actions_default_workflow_permissions_source
      config.source(KEY)
    end

    def set_default_workflow_permissions(value, actor)
      if value != "write"
        unless ALLOWED_VALUES.include? value
          raise Error.new("Invalid permission value: #{value}")
        end
        config.set!(KEY, value, actor)
      else
        config.delete(KEY, actor)
      end
      instrument "set_default_workflow_permissions", actor: actor, default_workflow_permissions_value: value
    end

    # Getter/Setters for actions_workflow_permission_can_approve_pr
    # if option is not present, default value is true
    def actions_workflow_permission_can_approve_pr?
      config.get(KEY_PR_APPROVAL_COUNTS).nil?
    end

    def actions_workflow_permission_can_allow_pr_approval?
      !config.inherited?(KEY_PR_APPROVAL_COUNTS)
    end

    def actions_workflow_permission_can_approve_pr_source
      config.source(KEY_PR_APPROVAL_COUNTS)
    end

    def set_actions_workflow_permission_can_approve_pr(value, actor)
      if value == true
        # delete value will result in .nil? -> true
        config.delete(KEY_PR_APPROVAL_COUNTS, actor)
      elsif value == false
        # will set the config value to false
        config.disable(KEY_PR_APPROVAL_COUNTS, actor)
      else
        raise Error.new("Invalid value for workflow permission can approve PR: '#{value}'. Valid values are: '#{ALLOWED_VALUES_PR_APPROVAL_COUNTS}'")
      end
      instrument "set_workflow_permission_can_approve_pr", actor: actor, workflow_permission_can_approve_pr_value: value
    end

  end
end
