# typed: true
# frozen_string_literal: true

module Navigation
  module Repository
    class GraphsView
      attr_reader :current_user, :current_repository

      def initialize(current_user:, current_repository:)
        @current_user = current_user
        @current_repository = current_repository
      end

      def show_community?
        GitHub.community_profile_enabled? &&
          current_repository.plan_supports?(:insights) &&
          current_repository.public? &&
          !current_repository.fork?
      end

      def show_community_insights?
        current_repository.can_view_community_insights?(current_user)
      end

      def show_dependency_graph?
        GitHub.dependency_graph_enabled? && (
          !GitHub.enterprise? || current_repository.dependency_graph_enabled?
        )
      end

      def show_actions_usage_metrics?
        current_user&.feature_flag_enabled?(:actions_usage_metrics, default: false) && actions_enabled_for_repo?
      end

      def actions_enabled_for_repo?
        return false unless !current_repository.nil? && ((GitHub.actions_enabled? && !current_repository.actions_disabled?) || show_only_required_workflows?)
        true
      end

      def show_only_required_workflows?
        current_repository.actions_disabled? && !current_repository.actions_disabled_by_owner? && current_repository.workflows.required.not_deleted.any?
      end

      def show_people?
        return false unless current_repository.owner.organization?
        current_repository.owner.adminable_by?(current_user)
      end
    end
  end
end
