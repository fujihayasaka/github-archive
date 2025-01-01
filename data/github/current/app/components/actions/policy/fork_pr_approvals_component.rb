# typed: true
# frozen_string_literal: true

module Actions
  module Policy
    class ForkPrApprovalsComponent < ApplicationComponent
      def initialize(entity:, action:)
        @entity = entity
        @action = action
      end

      def render?
        if !GitHub.enterprise? && !@entity.enterprise_managed_user_enabled?
          return @entity.can_write_organization_actions_settings?(current_user) if @entity.is_a?(Organization)
          true
        end
      end
    end
  end
end
