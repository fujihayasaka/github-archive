# typed: true
# frozen_string_literal: true

class Site::Readme::Home::DeveloperStoriesSectionComponent < ApplicationComponent
  def initialize(stories:)
    @stories = stories
  end

  def render?
    @stories.present?
  end

  def primary_story
    @stories.first
  end

  def secondary_stories
    @stories.drop(1).take(3)
  end
end
