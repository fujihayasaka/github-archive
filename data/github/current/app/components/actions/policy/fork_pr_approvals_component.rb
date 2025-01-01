# typed: true
# frozen_string_literal: true

module Actions
  module Policy
    class ForkPrApprovalsComponent < ApplicationComponent
      include GitHub::Memoizer

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

      memoize def use_new_copy?
        @entity.feature_flag_enabled?(:actions_workflow_approvals_new_copy, default: true)
      end

      def approving_runs_docs_url
        "#{GitHub.help_url}/actions/managing-workflow-runs/approving-workflow-runs-from-public-forks"
      end

    end
  end
end
