# typed: true
# frozen_string_literal: true

module OnboardingTasks
  class AbstractTask
    extend T::Sig
    extend T::Helpers

    abstract!

    include AnalyticsHelper
    include UrlHelpers
    include UrlHelper

    sig { returns(Taskable) }
    attr_reader :taskable

    sig { returns(T::Hash[String, T.untyped]) }
    attr_reader :attributes

    sig { returns(Symbol) }
    attr_reader :task_key

    sig { returns(Symbol) }
    attr_reader :context

    sig { params(user: T.nilable(User), taskable: Taskable, attributes: T::Hash[String, T.untyped]).void }
    def initialize(user:, taskable:, attributes: {})
      @user = T.let(user, T.nilable(User))
      @taskable = T.let(taskable, Taskable)
      @attributes = T.let(attributes, T::Hash[String, T.untyped])
      @task_key = T.let(self.class.task_key, Symbol)
      @context = T.let(self.class.context, Symbol)
    end

    # Gets the context which the task is defined. Used to return uncompleted tasks for that specific context.
    #
    # @example If you have a task defined at `OnboardingTasks::EnterpriseCloud::SomeTask`
    #   OnboardingTasks::EnterpriseCloud::SomeTask.context => :enterprise_cloud
    #
    # @return [Symbol] the context name where the task is defined that can be used on
    #                  OnboardingTasks::Onboard::ALL_BY_CONTEXT
    sig { returns(Symbol) }
    def self.context
      name&.deconstantize.split("::").last.underscore.to_sym
    end

    sig { returns(Symbol) }
    def self.task_key
      self.name&.demodulize.underscore.to_sym
    end

    sig { abstract.returns(T::Boolean) }
    def verify_task; end

    sig { abstract.returns(String) }
    def title; end

    sig { abstract.returns(T.nilable(String)) }
    def task_link; end

    sig { returns(T.nilable(Symbol)) }
    def octicon
      nil
    end

    sig { abstract.returns(T.nilable(String)) }
    def icon_path; end

    sig { returns(T::Boolean) }
    def enabled_for_user?
      true
    end

    sig { returns(T::Boolean) }
    def enabled_for_plan?
      true
    end

    sig { returns(T::Hash[String, T.untyped]) }
    def link_data_attributes
      analytics_click_attributes(category: "Onboarding Task", action: "click on onboarding task", label: "task:#{task_key};type:#{context}")
    end

    sig { returns(T::Boolean) }
    def completed?
      return @completed if defined?(@completed)

      @completed = (taskable.completed_onboarding_tasks.include?(task_key) || verify_and_store_if_completed)
    end

    sig { returns(T::Boolean) }
    def complete
      return true if taskable.completed_onboarding_tasks.include?(task_key)

      result = taskable.complete_task(task_key)

      track_completion
      result
    end

    private

    sig { returns(T.nilable(User)) }
    attr_reader :user

    sig { void }
    def track_completion
      GlobalInstrumenter.instrument("onboarding_task.complete", {
        user: @user,
        type: context,
        task: task_key,
        completed_tasks: taskable.completed_onboarding_tasks,
        remaining_tasks: Onboard.remaining_tasks(taskable, @user, context),
        taskable: @taskable,
      })
    end

    sig { returns(T::Boolean) }
    def verify_and_store_if_completed
      verify_task ? complete : false
    end
  end
end
