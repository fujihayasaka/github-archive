# typed: true
# frozen_string_literal: true

module GitHub
  # A helper class meant to be used as a tokenizer for validates_length_of
  # validations in models. The tokenizer needs to respond to length, as
  # that value is what's used to compare against. So here we just call
  # bytesize on the wrapped string instead of allowing the validation
  # to call length directly on it, which only counts characters.
  class BytesizeTokenizer
    def initialize(str)
      @wrapped_str = str
    end

    def length
      @wrapped_str.bytesize
    end

    def size
      @wrapped_str.bytesize
    end
  end
end
