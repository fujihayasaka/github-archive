module Hydro
  class FallbackSink
    extend Forwardable

    attr_reader :primary

    def_delegators :primary,
      :start_batch,
      :flush_batch,
      :add_to_batch,
      :batchable?,
      :batching?,
      :flushable?,
      :messages

    def initialize(primary:, fallback:)
      @primary = primary
      @fallback = fallback
      @validate = @primary.respond_to?(:validate_messages)
    end

    def sink
      @primary.sink
    end

    def write(messages, options = {})
      begin
        result = @primary.write(messages, options)
        return result if result.success?
      rescue => e
        result = Hydro::Sink::Result.failure(e)
      end

      if result.error.is_a?(Hydro::GatewaySink::DeliveryFailure)
        messages = result.error.failures.map { |failure| failure[:message] }
      end

      if result.error
        GitHub.dogstats.increment("hydro_client.fallback_sink.error", tags: ["error:#{result.error}"])
      end

      @fallback.write(messages, options)
    end

    def validate_messages(*args)
      @primary.validate_messages(*args) if @validate
    end

    def close
      @primary.close
      @fallback&.close
    end
  end
end
