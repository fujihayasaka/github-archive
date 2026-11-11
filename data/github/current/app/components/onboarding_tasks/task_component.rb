# typed: true
# frozen_string_literal: true

class OnboardingTasks::TaskComponent < ApplicationComponent
  DEFAULT_VARIANT = :medium

  VARIANT_MAPPINGS = {
    :small => {
      icon_wrapper: "pr-3",
      icon_custom_style: "opacity: 0.2;",
      icon_size: :small,
      list_wrapper: "my-3",
      task_link: "flex-items-center",
      tag_type: :li,
    },
    :inline => {
      icon_wrapper: "mr-x",
      icon_size: :medium,
      list_wrapper: "d-flex flex-items-center h5 border rounded-2 color-border-muted color-shadow-large color-bg-subtle hover-grow no-underline px-3 py-2 my-3",
      task_link: "btn-link no-underline",
      title_wrapper: "px-3",
      tag_type: :span,
    },
    :multiline => {
      icon_wrapper: "p-3",
      icon_custom_style: "opacity: 0.2;",
      icon_size: :small,
      list_wrapper: "col-lg-4",
      task_link: "width-full Box flex-column flex-justify-start",
      title_size: "h5 lh-condensed",
      title_wrapper: "px-3 pb-3",
      tag_type: :li,
    },
    DEFAULT_VARIANT => {
      icon_wrapper: "p-3",
      icon_custom_style: "opacity: 0.2;",
      icon_size: :small,
      list_wrapper: "col-lg-4 mb-4 mb-lg-0",
      task_link: "width-full Box flex-column flex-justify-start",
      title_size: "h5 lh-condensed",
      title_wrapper: "px-3 pb-3",
      tag_type: :li,
    },
  }.freeze
  VARIANT_OPTIONS = VARIANT_MAPPINGS.keys

  attr_reader :task, :body, :complete_task_url
  delegate :completed?, to: :task

  # @param task [OnboardingTasks::AbstractTask] The task itself.
  # @param body [String] The body of the text for the task
  # @param variant [Symbol] The variant of the task that will be rendered.
  #   See {VARIANT_OPTIONS} for available options.
  def initialize(task:, body: "", variant: DEFAULT_VARIANT, complete_task_url: nil)
    @task = task
    @body = body
    @variant = fetch_or_fallback(VARIANT_OPTIONS, variant, DEFAULT_VARIANT)
    @complete_task_url = complete_task_url
  end

  def render?
    @task.enabled_for_user? && @task.enabled_for_plan?
  end

  def display_body?
    @body.present? && @variant != :small
  end

  def content_wrapper(&block)
    content_tag(task.task_link ? :a : :div, href: task.task_link, data: { **link_data_attributes, action: "click:task-component#completeTask" }, class: task_link_classes) do
      yield
    end
  end

  private

  def link_data_attributes
    task.link_data_attributes
  end

  def variant_mapping(attribute)
    VARIANT_MAPPINGS[@variant][attribute.to_sym]
  end

  def task_link_classes
    class_names(
      "position-relative height-full overflow-hidden d-flex",
      variant_mapping(:task_link),
      { "no-underline" => task.task_link, "color-bg-subtle" => completed?, "color-shadow-medium hover-grow" => !completed? && (@variant == :medium || @variant == :multiline) }
    )
  end
end
