# typed: true
# frozen_string_literal: true

class Site::Readme::Topics::TopicsComponent < ApplicationComponent
  def initialize(topics_with_stories:)
    @topics_with_stories = topics_with_stories
  end

  def render?
    @topics_with_stories.present?
  end
end
