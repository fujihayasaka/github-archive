# typed: true
# frozen_string_literal: true

class Site::Readme::Shared::MoreStoriesComponent < ApplicationComponent
  def initialize(stories:)
    @more_stories = stories
  end

  def render?
    @more_stories.present?
  end
end
