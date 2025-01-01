# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    # AqueductHydroMessageRelay is a development-only lightweight implementation
    # of what aqueduct-bridge does. Instead of loading hydro-schemas bridge
    # configs, it uses a hardcoded topic-to-queue mapping to relay hydro
    # messages into aqueduct for processing.
    class AqueductHydroMessageBridge < BaseProcessor
      default_to_write_connection!

      DEFAULT_GROUP_ID = "aqueduct_hydro_message_bridge"

      options[:session_timeout] = 60.seconds
      options[:socket_timeout] = 65.seconds
      options[:start_from_beginning] = false

      # Public: Configure the Hydro processor
      def setup(**kwargs)
        options[:group_id] ||= DEFAULT_GROUP_ID

        options[:subscribe_to] = Regexp.new(
          topic_mapping.keys.map { |topic| "\\A" + Regexp.escape(topic) + "\\z" }.join("|")
        )

        @aqueduct_clients = {
          GitHub.aqueduct_app_name => GitHub.aqueduct_primary
        }
      end

      # Public: Process a single Hydro message
      #
      # message - The Hydro message to process
      #
      # Returns nothing
      def process_message(message)
        topic_mapping.fetch(message.topic).each do |app_queue_mapping|
          aqueduct_client_for(app_queue_mapping["app"]).send_job(
            queue: app_queue_mapping["queue"],
            payload: message.source_message.value, # protobuf bytes
            headers: message.headers.merge({
              "kafka-cluster" => Rails.env.to_s,
              "hydro-encoding" => "protobuf",
              "topic" => message.topic,
              "partition" => message.partition.to_s,
              "offset" => message.offset.to_s,
            })
          )
        end
      end

      private

      def aqueduct_client_for(app_name)
        @aqueduct_clients[app_name] ||= GitHub.build_aqueduct_client(app: app_name)
      end

      def topic_mapping
        return @topic_mapping if @topic_mapping.present?

        mapping_file = IO.read(Rails.root / "config/aqueduct_hydro_message_bridge/#{GitHub.runtime.current}.yml")
        @topic_mapping = YAML.load(
          ERB.new(mapping_file).result
        )
      end
    end
  end
end
