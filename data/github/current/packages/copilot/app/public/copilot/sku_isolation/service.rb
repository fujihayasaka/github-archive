# typed: strict
# frozen_string_literal: true

module Copilot
  class SKUIsolation
    # This creates an object with the given proc that returns a host, and
    # supports safe construction of an HTTPS endpoint.
    class Service
      extend T::Sig

      include GitHub::Memoizer

      sig { params(block: T.proc.returns(String)).void }
      def initialize(&block)
        @host = T.let(block, T.proc.returns(String))
      end

      sig { returns(String) }
      memoize def host
        @host.call
      end

      sig { returns(String) }
      memoize def endpoint
        # Workaround for URI bug: manually raise an error if host is blank
        raise URI::InvalidURIError, "Host cannot be blank" if host.nil? || host.strip.empty?

        URI::HTTPS.build(host: host).to_s
      end
    end
  end
end
