# typed: true
# frozen_string_literal: true

module Actions
  module Policy
    class ForkPullRequestComponent < ApplicationComponent
      include GitHub::Memoizer

      def initialize(entity:, action:)
        @entity = entity
        @action = action
      end

      def render?
        return @entity.can_write_organization_actions_settings?(current_user) if @entity.is_a?(Organization)
        true
      end

      def title
        return "Fork pull request workflows" if @entity.is_a?(Repository)
        "Fork pull request workflows in private repositories"
      end

      def show_description?
        !@entity.is_a?(Repository)
      end

      def description
        return "These settings apply to private repositories. Organization and repository administrators will only be able to change the settings that are enabled here." if @entity.is_a?(Business)
        "These settings apply to private repositories. Repository administrators will only be able to change the settings that are enabled here."
      end

      def require_approvals?
        @entity.actions_private_fork_pr_approvals_policy == Configurable::ActionsPrivateForkPrApprovals::READ_ONLY_USERS
      end

      memoize def can_disable_require_approvals?
        @entity.can_enable_fork_pr_workflows? && @entity.can_disable_actions_private_fork_pr_approvals?
      end

    end
  end
end
