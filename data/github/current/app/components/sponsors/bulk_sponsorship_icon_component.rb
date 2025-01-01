# typed: true
# frozen_string_literal: true

module Sponsors
  class BulkSponsorshipIconComponent < ApplicationComponent
    def initialize(size: 16, **system_arguments)
      @color = system_arguments[:color] || :sponsors
      @classes = system_arguments[:classes] || "octicon"
      @width = system_arguments[:width] || size
      @height = system_arguments[:height] || size
      @system_arguments = system_arguments
    end

    private

    attr_reader :title, :system_arguments, :color, :classes, :height, :width

    def render?
      GitHub.sponsors_enabled?
    end
  end
end
