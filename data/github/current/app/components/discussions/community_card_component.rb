# typed: true
# frozen_string_literal: true

module Discussions
  class CommunityCardComponent < ApplicationComponent
    def initialize(image:, title:, link:, description:)
      @image = image
      @title = title
      @link = link
      @description = description
    end

    private

    attr_reader :image, :title, :link, :description
  end
end
