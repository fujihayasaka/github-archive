# typed: strict
# frozen_string_literal: true

module OnboardingTasks
  module Organizations
    class BranchProtectionRule < Base
      extend T::Sig

      sig { override.returns(String) }
      def title
        "Create a branch protection rule"
      end

      sig { returns(T::Boolean) }
      def require_demo_repository?
        true
      end

      sig { override.returns(T.nilable(String)) }
      def task_link
        return unless (repo = demo_repo)
        new_branch_protection_rule_path(organization, repo.name, enable_tip: true)
      end

      sig { override.returns(T::Boolean) }
      def verify_task
        return false unless (repo = demo_repo)

        begin
          repo.protected_branches.limit_execution_time.exists?
        rescue ActiveRecord::StatementTimeout
          false
        end
      end

      sig { override.returns(String) }
      def icon_path
        "modules/dashboard/suggestions/protected-branches.svg"
      end
    end
  end
end
