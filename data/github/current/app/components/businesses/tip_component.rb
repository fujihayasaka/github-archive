# typed: true
# frozen_string_literal: true

class Businesses::TipComponent < ApplicationComponent
  include SvgHelper

  attr_reader :business, :content_media, :task, :content_media_url, :container_class
  delegate :completed?, to: :task

  # @param business [Business]
  # @param show_tip [Boolean] If the tip must be displayed or not
  # @param content_media [String] The path of the media that will be displayed on the right side of the component
  # @param task [OnboardingTasks::AbstractTask] The task itself.
  def initialize(business:, show_tip: false, content_media: nil, task:, content_media_url: nil, container_class: nil)
    @business = business
    @content_media = content_media
    @content_media_url = content_media_url
    @show_tip = show_tip
    @task = task
    @container_class = container_class
  end

  # @return [Boolean]
  def show_tip?
    @show_tip
  end

  # @return [Boolean]
  def render?
    show_tip? && !task.completed?
  end
end
