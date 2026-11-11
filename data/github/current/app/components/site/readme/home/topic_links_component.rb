# typed: true
# frozen_string_literal: true

class Site::Readme::Home::TopicLinksComponent < ApplicationComponent
  def initialize(topics:)
    @topics = topics
  end

  def topics
    @topics
  end
end
