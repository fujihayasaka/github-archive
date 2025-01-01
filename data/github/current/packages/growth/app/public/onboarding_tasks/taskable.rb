# typed: strict
# frozen_string_literal: true

module OnboardingTasks
  module Taskable
    extend T::Sig
    extend T::Helpers

    abstract!

    requires_ancestor { ActiveRecord::Base }

    sig { abstract.returns(T::Array[Symbol]) }
    def completed_onboarding_tasks; end

    sig { params(task_key: Symbol).returns(T::Boolean) }
    def complete_task(task_key)
      ActiveRecord::Base.connected_to(role: :writing) do
        update(completed_onboarding_tasks: completed_onboarding_tasks << task_key)
      end
    end
  end
end
