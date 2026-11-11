# typed: true
# frozen_string_literal: true

class Site::Readme::Home::FeaturedSectionComponent < ApplicationComponent
  def initialize(stories:)
    @stories = stories
  end

  def render?
    @stories.present?
  end

  def featured_story
    @stories.first
  end
end
