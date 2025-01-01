# typed: true
# frozen_string_literal: true

module Hookshot
  class PayloadTooLarge < HookshotError
    attr_reader :payload, :size

    def initialize(payload, size)
      @payload = payload
      @size = size
      super size
    end
  end
end
