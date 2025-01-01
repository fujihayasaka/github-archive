# typed: true
# frozen_string_literal: true

module Discussions
  class BodyComponent < ApplicationComponent
    def initialize(discussion:, timeline:)
      @discussion = discussion
      @timeline = timeline
    end

    private

    attr_reader :discussion, :timeline
  end
end
