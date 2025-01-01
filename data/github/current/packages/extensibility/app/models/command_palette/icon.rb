# typed: true
# frozen_string_literal: true

module CommandPalette
  class Icon
    attr_reader :type

    def initialize(type:)
      @type = type
    end

    def as_json(*)
      raise NotImplementedError, "Please implement `##{__method__}` on your icon"
    end

    def ==(other)
      to_json == other.to_json
    end
  end
end
