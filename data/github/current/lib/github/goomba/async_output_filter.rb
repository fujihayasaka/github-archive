# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  class AsyncOutputFilter < OutputFilter
    # The main filter entry point.
    #
    # html - A String of output from the WarpPipe.
    #
    # Returns Promise<String>.
    def async_call(html)
      raise NotImplementedError
    end

    def call(html)
      async_call(html).sync
    end
  end
end
