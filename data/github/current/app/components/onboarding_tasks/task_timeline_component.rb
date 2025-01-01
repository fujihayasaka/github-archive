# typed: strict
# frozen_string_literal: true

class OnboardingTasks::TaskTimelineComponent < ApplicationComponent
  sig { returns(OnboardingTasks::AbstractTask) }
  attr_reader :task

  sig { returns(String) }
  attr_reader :body

  sig { returns(T::Boolean) }
  attr_reader :last_item

  delegate :completed?, to: :task

  # @param task [OnboardingTasks::AbstractTask] The task itself.
  # @param body [String] The body of the text for the task
  sig do
    params(
      task: OnboardingTasks::AbstractTask,
      body: String,
      last_item: T::Boolean,
    ).void
  end
  def initialize(task:, body: "", last_item: false)
    @task = task
    @body = body
    @last_item = last_item
  end

  sig { returns(Symbol) }
  def status_color
    completed? ? :open : :subtle
  end

  sig { returns(Symbol) }
  def status_icon
    completed? ? :"check-circle-fill" : :circle
  end

  sig { returns(Symbol) }
  def header_color
    completed? ? :muted : :default
  end

  sig { returns(Integer) }
  def margin_btm
    if last_item
      -3
    else
      4
    end
  end

  sig { returns(String) }
  def extra_styles
    completed? ? "" : "color: var(--borderColor-muted) !important;"
  end

  private

  sig { returns(T::Hash[String, T.untyped]) }
  def link_data_attributes
    task.link_data_attributes
  end
end
