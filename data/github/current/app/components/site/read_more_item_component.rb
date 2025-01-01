# typed: true
# frozen_string_literal: true

module Site
  class ReadMoreItemComponent < ApplicationComponent
    include SvgHelper

    def initialize(text:, url:, header: "Read", analytics: nil)
      @header = header
      @text = text
      @url = url
      @analytics = analytics
    end
  end
end
