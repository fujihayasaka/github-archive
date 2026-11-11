# typed: true
# frozen_string_literal: true

class Site::Readme::Shared::LinkTextComponent < ApplicationComponent
  include Site::ReadmeHelper

  def initialize(story:, heading_class: nil, heading_level: 3, subtitle_class: nil, subtitle: true, include_link: true)
    @story = story
    @heading_class = heading_class
    @subtitle_class = subtitle_class
    @subtitle = subtitle
    @include_link = include_link
    @heading_level = "h#{heading_level}"
  end

  def show_preview
    !@story[:published?]
  end

  def with_links?
    @include_link
  end

  def show_subtitle
    @subtitle
  end

  def heading_class
    return @heading_class if @heading_class.present?

    "h4-mktg font-alt-mktg lh-condensed-mktg"
  end

  def subtitle_class
    return @subtitle_class if @subtitle_class.present?

    "f4-mktg"
  end
end
