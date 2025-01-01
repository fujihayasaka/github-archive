# typed: true
# frozen_string_literal: true

module Actions
  module Policy
    class DefaultWorkflowPermissionsComponent < ApplicationComponent
      def initialize(entity:, action:)
        @entity = entity
        @action = action
      end

      def render?
        return @entity.can_write_organization_actions_settings?(current_user) if @entity.is_a?(Organization)
        true
      end

      def entity_type
        return "enterprise" if @entity.is_a? Business
        return "organization" if @entity.is_a? Organization
        "repository"
      end

    end
  end
end
