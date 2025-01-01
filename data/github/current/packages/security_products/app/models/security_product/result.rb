# typed: true
# frozen_string_literal: true

module SecurityProduct
  class Result
    attr_reader :value, :error
    def initialize(value, error = nil)
      @value = value
      @error = error
    end

    def error?
      !error.nil?
    end

    def to_ary
      to_a
    end

    def to_a
      [value, error]
    end
  end
end
