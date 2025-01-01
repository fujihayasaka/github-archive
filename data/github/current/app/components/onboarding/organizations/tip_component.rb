# typed: strict
# frozen_string_literal: true

class Onboarding::Organizations::TipComponent < ApplicationComponent
  include SvgHelper

  sig { returns(Organization) }
  attr_reader :organization

  sig { returns(OnboardingTasks::AbstractTask) }
  attr_reader :task

  sig { returns(T::Boolean) }
  attr_reader :show_tip

  sig { returns(T.nilable(String)) }
  attr_reader :content_media

  sig { returns(T.nilable(String)) }
  attr_reader :content_media_url

  sig { returns(T.nilable(String)) }
  attr_reader :tasks_path

  sig { returns(T.untyped) }
  attr_reader :system_arguments

  delegate :completed?, to: :task

  sig do
    params(
      organization: Organization,
      task: OnboardingTasks::AbstractTask,
      show_tip: T::Boolean,
      content_media: T.nilable(String),
      content_media_url: T.nilable(String),
      tasks_path: String,
      check_for_task_completion: T::Boolean,
      system_arguments: T.untyped
    ).void
  end
  def initialize(
    organization:,
    task:,
    show_tip: false,
    content_media: nil,
    content_media_url: nil,
    tasks_path: user_path(organization),
    check_for_task_completion: true,
    **system_arguments
  )
    @organization = organization
    @content_media = content_media
    @content_media_url = content_media_url
    @show_tip = show_tip
    @task = task
    @tasks_path = tasks_path
    @check_for_task_completion = check_for_task_completion
    @system_arguments = system_arguments

  end

  sig { returns(T::Boolean) }
  def render?
    return false unless show_tip
    return false if @check_for_task_completion && task.completed?
    true
  end
end
