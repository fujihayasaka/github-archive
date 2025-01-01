# typed: true
# frozen_string_literal: true

module CommandPalette
  class Action
    attr_reader :type, :description, :path

    def initialize(type:, description:, path:)
      @type = type
      @description = description
      @path = path
    end

    def as_json(*)
      {
        type: type,
        description: description,
        path: path,
      }
    end
  end
end
