# typed: strict
# frozen_string_literal: true

require "faraday"
require "freno/client"

module Freno
  # GHES treats unavailable Freno as disabled, while retaining lag and operator throttles.
  class FailOpenClient < Client
    FAIL_OPEN_METRIC = "github.freno.enterprise.fail_open"
    FAIL_OPEN_SAMPLE_RATE = 0.01
    NORMAL_STATUS_CODES = [200, 417, 429].freeze

    # Validate before replication_delay discards the HTTP status and caches the value.
    class ResponseValidator < Faraday::Middleware
      sig { params(env: Faraday::Env).void }
      def on_complete(env)
        return if NORMAL_STATUS_CODES.include?(env.status)

        raise Freno::Error, "unexpected Freno status: #{env.status.inspect}"
      end
    end
    private_constant :ResponseValidator

    sig do
      params(
        faraday: Faraday::Connection,
        block: T.nilable(T.proc.params(client: Client).void)
      ).void
    end
    def initialize(faraday, &block)
      faraday.use ResponseValidator
      super(faraday, &block)
    end

    private

    sig { params(request: Symbol, kwargs: T.untyped).returns(T.any(Client::Result, Numeric)) }
    def perform(request, **kwargs)
      result = super

      if request == :replication_delay
        raise Freno::Error, "unexpected replication delay from Freno" unless result.is_a?(Numeric)
      elsif !result.is_a?(Client::Result) || !NORMAL_STATUS_CODES.include?(result.code)
        # With raise_on_timeout disabled, the gem returns a synthetic 408 instead of raising.
        raise Freno::Error, "unexpected check result from Freno"
      end

      result
    rescue Freno::Error
      GitHub.dogstats.increment(FAIL_OPEN_METRIC, sample_rate: FAIL_OPEN_SAMPLE_RATE)
      request == :replication_delay ? 0.0 : Client::Result.new(200)
    end
  end
end
