# typed: true
# frozen_string_literal: true

module Explore
  class ListItemTopicComponent < ApplicationComponent
    def initialize(topic:)
      @topic = topic
    end

    private

    def render?
      @topic.present?
    end
  end
end
