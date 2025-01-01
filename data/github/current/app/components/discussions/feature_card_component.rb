# typed: true
# frozen_string_literal: true

module Discussions
  class FeatureCardComponent < ApplicationComponent
    def initialize(image_light:, image_dark:, add_label:, label_text: "Coming soon", title:, description:)
      @image_light = image_light
      @image_dark = image_dark
      @add_label = add_label
      @label_text = label_text
      @title = title
      @description = description
    end

    private

    attr_reader :image_light, :image_dark, :add_label, :label_text, :title, :description
  end
end
