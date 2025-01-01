# typed: true
# frozen_string_literal: true

module Discussions
  class CreatedIssueEventDescriptionComponent < ApplicationComponent
    def initialize(event:, timeline:)
      @event = event
      @timeline = timeline
    end

    attr_reader :event, :timeline
  end
end
