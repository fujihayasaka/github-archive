# typed: true
# frozen_string_literal: true

module Packages
  class IconComponent < ApplicationComponent
    include SvgHelper

    # including docker and container is temporary for backwards compat during v1/v2 migration.
    # once things are moved to container, docker can be deprecated.
    SUPPORTED_ICONS = %w(docker maven npm nuget rubygems container).freeze

    def initialize(type: nil, size: 16, **args)
      @type, @size, @args = type, size, args
    end

    private

    def asset_path
      if SUPPORTED_ICONS.include?(@type&.downcase.to_s)
        "icons/packages/#{@type.downcase}.svg"
      end
    end
  end
end
