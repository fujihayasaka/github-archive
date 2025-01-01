# typed: true
# frozen_string_literal: true

module GitHub
  module AzureServiceBus
    class ConnectionConfiguration
      KEY_MAPPING = {
        default_host: "Endpoint",
        sas_key_name: "SharedAccessKeyName",
        sas_key: "SharedAccessKey"
      }.freeze

      def self.from_connection_string(connection_string)
        parsed_results = connection_string.split(";").map do |section|
          section.split("=", 2)
        end.to_h

        new(parsed_results)
      end

      def initialize(raw_configuration)
        @raw_configuration = raw_configuration
      end

      def default_host
        @default_host ||= URI(raw_configuration[KEY_MAPPING[:default_host]]).host
      end

      def sas_key_name
        @sas_key_name ||= raw_configuration[KEY_MAPPING[:sas_key_name]]
      end

      def sas_key
        @sas_key ||= raw_configuration[KEY_MAPPING[:sas_key]]
      end

      private

      attr_reader :raw_configuration
    end
  end
end
