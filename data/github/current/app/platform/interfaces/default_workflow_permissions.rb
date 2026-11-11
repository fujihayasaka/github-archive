# typed: true
# frozen_string_literal: true

module Platform
  module Interfaces
    module DefaultWorkflowPermissions
      include Platform::Interfaces::Base

      description "Specifies the default workflow permissions level for GITHUB_TOKENs."
      visibility :internal

      field :default_workflow_permissions, Enums::DefaultWorkflowPermissionsValue, "Indicates default workflow permissions level", method: :default_workflow_permissions, null: true

      def default_workflow_permissions
        @object.actions_default_workflow_permissions
      end
    end
  end
end
