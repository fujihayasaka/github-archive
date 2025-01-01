# typed: true
# frozen_string_literal: true

class Businesses::CompletedGuidanceComponent < ApplicationComponent
  include BusinessesHelper

  attr_reader :business, :completed_task, :container_class

  # @param business [Business]
  # @param completed_task [OnboardingTasks::AbstractTask] The task that was completed.
  # @param show_tip [Boolean] If the tip must be displayed or not
  # @param container_class [String] The class that will be used on the container wrapping the component.
  def initialize(business:, completed_task:, show_tip: false, container_class: nil)
    @business = business
    @completed_task = completed_task
    @show_tip = show_tip
    @container_class = container_class
  end

  # @return [Boolean]
  def show_tip?
    @show_tip
  end

  # @return [Boolean]
  def render?
    show_tip? && completed_task.completed?
  end

  # @return [OnboardingTasks::AbstractTask, nil] An uncompleted task or `nil` if none.
  memoize def next_uncompleted_task
    OnboardingTasks::Onboard.next_uncompleted_task_for_context(business, current_user, @completed_task.context)
  end
end
