# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  # Base class for output filters. Output filters are passed a WarpPipe's
  # serialized document fragment after it has been processed by input, element,
  # and text filters.
  class OutputFilter < Filter
    # The main filter entry point.
    #
    # html - The HTML String output from the WarpPipe.
    #
    # Returns a modified String.
    def call(html)
      raise NotImplementedError
    end

    # Perform a filter on HTML with the given context.
    #
    # Returns a modified String and may modify the result Hash.
    def self.call(html, context = nil, result = nil)
      self.new(context, result).call(html)
    end
  end
end
