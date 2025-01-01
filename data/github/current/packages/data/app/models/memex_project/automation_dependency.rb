# typed: true
# frozen_string_literal: true

class MemexProject
  module AutomationDependency
    extend ActiveSupport::Concern
    extend T::Helpers
    include GitHub::Memoizer

    requires_ancestor { MemexProject }

    sig { returns(T::Boolean) }
    def automation_enabled?
      return @automations_enabled if defined?(@automations_enabled)
      @automations_enabled = if GitHub.enterprise?
        GitHub.projects_automation_enabled?
      else
        true
      end
    end

    sig { params(user: T.nilable(User)).returns(T::Boolean) }
    def automation_enabled_for_user?(user)
      automation_enabled? && viewer_can_write?(user)
    end

    sig { returns(Integer) }
    def auto_add_creation_limit
      @auto_add_creation_limit ||= begin
        # See config/plans.yml for plan limits
        plan_limit = owner.plan_limit(:projectsv2_auto_add_workflows)
        employee_limit = if owner.employee?
          MemexProjectWorkflow::WorkflowLimitsDependency::EMPLOYEE_AUTO_ADD_CREATION_LIMIT
        else
          MemexProjectWorkflow::WorkflowLimitsDependency::DEFAULT_CREATION_LIMIT
        end

        [plan_limit, employee_limit].max
      end
    end
  end
end
