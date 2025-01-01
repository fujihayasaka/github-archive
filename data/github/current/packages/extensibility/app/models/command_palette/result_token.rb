# typed: true
# frozen_string_literal: true
module CommandPalette
  class ResultToken
    attr_reader :text, :type, :id, :value

    def initialize(text:, type:, id:, value: nil)
      @text = text
      @type = type
      @value = value || @text
      @id = id
    end

    def as_json(*)
      {
        text: text,
        type: type,
        id: id,
        value: value
      }
    end
  end
end
