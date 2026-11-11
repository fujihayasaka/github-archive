# typed: strict
# frozen_string_literal: true

module GitHub
  module AzureServiceBus
    class ConnectionConfiguration
      KEY_MAPPING = T.let({
        default_host: "Endpoint",
        sas_key_name: "SharedAccessKeyName",
        sas_key: "SharedAccessKey"
      }.freeze, T::Hash[Symbol, String])

      sig { params(connection_string: String).returns(ConnectionConfiguration) }
      def self.from_connection_string(connection_string)
        parsed_results = T.let({}, T::Hash[String, String])

        connection_string.split(";").each do |section|
          parts = section.split("=", 2)
          key = parts[0]
          value = parts[1] || ""
          parsed_results[key] = value if key && !key.empty?
        end

        new(parsed_results)
      end

      sig { params(raw_configuration: T::Hash[String, String]).void }
      def initialize(raw_configuration)
        @raw_configuration = T.let(raw_configuration, T::Hash[String, String])
        @default_host = T.let(nil, T.nilable(String))
        @sas_key_name = T.let(nil, T.nilable(String))
        @sas_key = T.let(nil, T.nilable(String))
      end

      sig { returns(String) }
      def default_host
        @default_host ||= T.must(URI(T.must(raw_configuration[T.must(KEY_MAPPING[:default_host])])).host)
      end

      sig { returns(String) }
      def sas_key_name
        @sas_key_name ||= T.must(raw_configuration[T.must(KEY_MAPPING[:sas_key_name])])
      end

      sig { returns(String) }
      def sas_key
        @sas_key ||= T.must(raw_configuration[T.must(KEY_MAPPING[:sas_key])])
      end

      private

      sig { returns(T::Hash[String, String]) }
      attr_reader :raw_configuration
    end
  end
end
