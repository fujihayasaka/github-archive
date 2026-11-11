# typed: true
# frozen_string_literal: true

class Site::Readme::Topics::StoryListComponent < ApplicationComponent
  def initialize(topic:, stories:)
    @topic = topic
    @stories = stories
  end

  def render?
    @stories.present?
  end
end
