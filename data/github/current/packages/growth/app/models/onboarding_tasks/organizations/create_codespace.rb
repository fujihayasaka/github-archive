# typed: strict
# frozen_string_literal: true

module OnboardingTasks
  module Organizations
    class CreateCodespace < Base
      sig { returns(T::Boolean) }
      def enabled_for_user?
        organization.codespaces_feature_enabled?
      end

      sig { override.returns(String) }
      def title
        "Create a Codespace"
      end

      sig { returns(T::Boolean) }
      def require_demo_repository?
        true
      end

      sig { override.returns(T.nilable(String)) }
      def task_link
        return unless (repo = demo_repo)
        "#{repository_codespaces_path(repo)}?enable_codespaces_tip=true"
      end

      sig { override.returns(T::Boolean) }
      def verify_task
        return false unless (repo = demo_repo)

        begin
          Codespace.limit_execution_time.where(repository_id: repo.id).exists?
        rescue ActiveRecord::StatementTimeout
          false
        end
      end

      sig { override.returns(String) }
      def icon_path
        "modules/dashboard/suggestions/code.svg"
      end
    end
  end
end
