# typed: true
# frozen_string_literal: true
class Site::Contentful::CustomerStories::StoryGridComponent < ApplicationComponent
  def initialize(stories, classes: nil, **custom_options)
    @stories = stories
    @classes = classes
    @custom_options = custom_options
  end

  def render?
    @stories.present?
  end

  private

  def options
    default_options.merge(@custom_options)
  end

  def default_options
    { class: container_classes, **test_selector_data_hash("customer-stories-grid") }
  end

  def container_classes
    class_names("d-flex flex-wrap gutter-md-spacious", @classes)
  end
end
