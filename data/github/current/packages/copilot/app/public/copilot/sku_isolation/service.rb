# typed: strict
# frozen_string_literal: true

module Copilot
  class SKUIsolation
    # This creates an object with the given proc that returns a host, and
    # supports safe construction of an HTTPS endpoint.
    class Service

      include GitHub::Memoizer

      sig { params(block: T.proc.returns(String)).void }
      def initialize(&block)
        @block = T.let(block, T.proc.returns(String))
      end

      sig { returns(String) }
      memoize def host
        # If the block rendered a URL with scheme, the #authority is the host
        # including port.
        if uri.scheme
          return T.cast(uri, T.any(URI::HTTP, URI::HTTPS)).authority
        end

        rendered
      end

      sig { returns(String) }
      memoize def endpoint
        # If the block rendered a URL with scheme, we should just return the
        # input.
        return rendered if uri.scheme

        URI::HTTPS.build(host: host).to_s
      end

      sig { returns(String) }
      memoize def rendered
        @block.call
      end

      private

      sig { returns(T.any(URI::Generic, URI::HTTP, URI::HTTPS)) }
      memoize def uri
        URI.parse(rendered)
      end
    end
  end
end
