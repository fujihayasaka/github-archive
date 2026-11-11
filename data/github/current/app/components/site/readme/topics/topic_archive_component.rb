# typed: true
# frozen_string_literal: true

class Site::Readme::Topics::TopicArchiveComponent < ApplicationComponent
  include SvgHelper

  def initialize(topic:, stories:)
    @topic = topic
    @stories = stories
  end
end
