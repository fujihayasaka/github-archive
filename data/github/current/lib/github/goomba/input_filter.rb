# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  # Base class for input filters. Input filters are passed a WarpPipe's input
  # before it has been parsed as HTML.
  class InputFilter < Filter
    module Encoding
      include GitHub::UTF8

      # Ensure that an InputFilter's output is UTF8 encoded
      def call(input)
        result = super(input)
        result.is_a?(String) ? utf8(result) : result
      end
    end

    def self.inherited(subclass)
      subclass.prepend InputFilter::Encoding
    end

    # The main filter entry point.
    #
    # input - The String input to the WarpPipe.
    #
    # Returns a modified String.
    def call(input)
      raise NotImplementedError
    end

    # Perform a filter on input with the given context.
    #
    # Returns a modified String and may modify the result Hash.
    def self.call(input, context = nil, result = nil)
      self.new(context, result).call(input)
    end
  end
end
