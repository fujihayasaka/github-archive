# typed: true
# frozen_string_literal: true

module Notifyd
  module Aqueduct
    APP = "notifyd"
    QUEUE = "notifyd_notify"
    SCHEMA = "notifyd.v0.Notify"

    # Header values
    SYSTEM = "aqueduct"
    HYDRO_ENCODING = "protobuf"

    # Error for when the service can't be reached or the circuit breaker is closed
    class UnavailableError < StandardError; end

    class Factory
      def initialize
        @clients = {}
      end

      def build(app:, **kwargs)
        @clients.fetch(app) do |key|
          # This lazy loads the client, creating it only once
          @clients[key] = GitHub.build_aqueduct_client(app: app, **kwargs)
        end
      end
    end

    # Encode a Protobuf message using Hydro's encoder and returns its bytes/encoded representation
    class ProtobufPayload
      def initialize(data, schema: SCHEMA, encoder: GitHub.hydro_encoder)
        @data = data
        @schema = schema
        @encoder = encoder
      end

      def bytes
        @bytes ||= @encoder.encode(@data, schema: @schema)
      end

      def bytesize
        bytes&.bytesize
      end

      def encoding
        # encoding is used to signify compression, but there is no compression here
        nil
      end
    end

    # Given an existing payload, deflate/compress it with Zlib::Deflate
    class DeflatedPayload
      ENCODING = "deflate"

      attr_reader :original

      def initialize(original)
        @original = original
      end

      def bytes
        @bytes ||= Zlib::Deflate.deflate(original.bytes)
      end

      def bytesize
        bytes&.bytesize
      end

      def encoding
        ENCODING
      end
    end

    def self.default_client_for(factory: nil)

      (factory || default_factory).build(
        app: app_name,
        url: GitHub.aqueduct_notifyd_url,
        circuit_breaker: GitHub.aqueduct_gateway_circuit_breaker,
        api_key: GitHub.aqueduct_notifyd_api_key,
        api_key_version: GitHub.aqueduct_notifyd_api_key_version,
      )
    end

    def self.default_factory
      @default_factory ||= Factory.new
    end

    def self.default_factory=(factory)
      @default_factory = factory
    end

    # Aqueduct app names follow the format: <app>-<environment>
    def self.app_name
      "#{APP}-production"
    end

    # Set specific header values for an Aqueduct message
    def self.populate_headers(headers, queue: QUEUE, payload: nil)
      headers[:published_to] = SYSTEM
      headers[:content_length] = payload&.bytesize
      headers[:content_encoding] = payload&.encoding
      # Same header set by aqueduct-bridge
      headers[:"hydro-encoding"] = HYDRO_ENCODING

      headers
    end
  end
end
