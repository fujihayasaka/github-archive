module Hydro
  class CutoverSink
    attr_reader :original, :cutover

    def initialize(original:, cutover:, toggle:)
      @original = original
      @cutover = cutover
      @toggle = toggle
    end

    def sink
      @original.sink
    end

    def start_batch
      @original.start_batch
      @cutover.start_batch
    end

    def flush_batch
      begin
        original_result = @original.flush_batch
      rescue => e
        original_error = e
      end

      begin
        cutover_result = @cutover.flush_batch
      rescue => e
        cutover_error = e
      end

      # If both the original sink and cutover sink raise an error, raise the original sink error.
      raise original_error if original_error
      raise cutover_error if cutover_error

      # If both the original sink and cutover sink return a failed result, return the origin sink result.
      return original_result if !original_result&.success?
      cutover_result
    end

    def close
      @original.close
      @cutover.close
    end

    def write(*args)
      if @toggle.call(*args)
        @cutover.write(*args)
      else
        @original.write(*args)
      end
    end

    def batchable?
      @original.batchable? && @cutover.batchable?
    end

    def batching?
      @original.batching? || @cutover.batching?
    end

    def add_to_batch(*args)
      if @toggle.call(*args)
        @cutover.add_to_batch(*args)
      else
        @original.add_to_batch(*args)
      end
    end

    def flushable?
      @original.flushable? || @cutover.flushable?
    end

    def messages
      @original.messages + @cutover.messages
    end

    private

    # Cutover happens on a per process basis rather than a per write basis so that a single process
    # isn't using both sinks and associated resources e.g. connections.
    class Actor
      attr_reader :flipper_id

      def initialize(hostname: Socket.gethostname, pid: Process.pid)
        @flipper_id = "#{hostname}:#{pid}"
      end

      def to_s
        @flipper_id
      end
    end
  end
end
