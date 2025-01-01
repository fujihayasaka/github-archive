# typed: true
# frozen_string_literal: true

module Hovercard::Contexts
  class Custom < Base
    attr_reader :message, :octicon

    def initialize(message, octicon)
      @message = message
      @octicon = octicon
    end

    def platform_type_name
      "GenericHovercardContext"
    end
  end
end
