# typed: true
# frozen_string_literal: true

module GitHub
  class BoundRetry
    DEFAULT_LIMIT = 5

    attr_reader :exceptions, :limit, :program, :on_exception_proc

    def self.with_bound_retry(*exceptions, limit: DEFAULT_LIMIT, on_exception: nil, &block)
      new(*T.unsafe(exceptions), limit: limit, on_exception: on_exception, &block).run
    end

    def initialize(*exceptions, limit: DEFAULT_LIMIT, on_exception: nil, &block)
      @exceptions = exceptions
      @limit = limit
      @program = block
      @on_exception_proc = on_exception
    end

    def on_exception(&block)
      @on_exception_proc = block
    end

    def run
      retry_count = 0
      begin
        program.call
      rescue *exceptions => e
        retry_count += 1
        on_exception_proc&.call(e, retry_count)
        retry if retry_count < limit
        raise
      end
    end
  end
end
