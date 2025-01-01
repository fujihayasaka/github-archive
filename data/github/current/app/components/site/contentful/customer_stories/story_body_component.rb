# typed: true
# frozen_string_literal: true

class Site::Contentful::CustomerStories::StoryBodyComponent < ApplicationComponent
  include Site::Contentful::RichTextHelper
  def initialize(body)
    @body = body
  end
end
