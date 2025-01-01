# typed: strict
# frozen_string_literal: true

module OnboardingTasks
  module AdvancedSecurity
    class TaskCardComponent < ApplicationComponent
      extend T::Sig

      sig { returns(OnboardingTasks::AdvancedSecurity::Base) }
      attr_reader :task
      delegate :completed?, :task_link, to: :task

      sig { returns T::Hash[Symbol, T.untyped] }
      attr_reader :system_arguments

      sig { returns T.nilable(String) }
      attr_reader :complete_task_with_click_url

      sig do
        params(
          task: OnboardingTasks::AdvancedSecurity::Base,
          complete_task_with_click_url: T.nilable(String),
          system_arguments: T.untyped,
        ).void
      end
      def initialize(task:, complete_task_with_click_url: nil, **system_arguments)
        @task = task
        @complete_task_with_click_url = complete_task_with_click_url
        @system_arguments = T.let({
          align_self: :auto,
          p: 3,
          col: 8,
          border: true,
          border_radius: 2,
          border_color: :muted,
          animation: :hover_grow,
          bg: :default,
      }.merge(system_arguments), T::Hash[T.untyped, T.untyped])
      end

      renders_one :description

      sig { returns(T::Boolean) }
      def render?
        @task.enabled_for_user?
      end
    end
  end
end
