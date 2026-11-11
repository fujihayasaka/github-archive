# typed: true
# frozen_string_literal: true

class Site::Readme::Shared::RecirculationStoryComponent < ApplicationComponent
  def initialize(recirculation_story:)
    @recirculation_story = recirculation_story
  end

  def label
    if @recirculation_story[:developer_story?]
      "Also in Developer Stories"
    elsif @recirculation_story[:guide?]
      "Also in Guides"
    elsif @recirculation_story[:podcast?]
      "Also on The ReadME Podcast"
    end
  end
end
