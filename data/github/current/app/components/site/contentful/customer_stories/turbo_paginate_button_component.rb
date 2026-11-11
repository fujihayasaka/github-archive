# typed: true
# frozen_string_literal: true

class Site::Contentful::CustomerStories::TurboPaginateButtonComponent < ApplicationComponent
  def initialize(url:, text: "", classes: nil, **button_options)
    @url = url
    @text = text
    @classes = classes
    @button_options = button_options
  end

  def call
    render Site::ButtonComponent.new(
      text: @text,
      url: @url,
      display: :flex,
      border: true,
      bg: :default,
      **options
    ) do
      content
    end
  end

  private

  def options
    {
      "data-turbo-stream": "",
      classes: classes,
      **@button_options
    }
  end

  def classes
    class_names("flex-justify-center flex-items-center", @classes)
  end
end
