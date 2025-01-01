# typed: true
# frozen_string_literal: true

class Site::Readme::Home::PodcastsSectionComponent < ApplicationComponent

  def initialize(stories:)
    @stories = stories
  end

  def render?
    @stories.present?
  end

  def podcasts
    @stories.take(2)
  end
end
