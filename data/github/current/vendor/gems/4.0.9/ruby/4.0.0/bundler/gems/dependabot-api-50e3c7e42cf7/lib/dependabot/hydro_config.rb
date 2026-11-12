# frozen_string_literal: true

module Dependabot
  module HydroConfig
    DEV_SINK_FILENAME = Rails.root.join("tmp/hydro.out")

    def hydro_site
      if Rails.env.production?
        JSON.parse(File.read("/etc/github/metadata.json")).fetch("site")
      else
        "localhost"
      end
    end

    def hydro_sink # rubocop:disable Metrics/MethodLength
      @hydro_sink ||=
        case Rails.env
        when "production"
          Hydro::KafkaSink.new(
            client_id: ENV["KAFKA_CLIENT_ID"],
            seed_brokers: ENV["HYDRO_KAFKA_BROKERS"].to_s.split,
            client_options: {
              ssl_ca_cert_file_path: ENV["HYDRO_KAFKA_CERT_PATH"],
            }
          )
        when "development"
          if ENV.key?("HYDRO_KAFKA_BROKERS")
            Hydro::KafkaSink.new(
              client_id: "dependabot-api-development",
              seed_brokers: ENV["HYDRO_KAFKA_BROKERS"].to_s.split
            )
          else
            FileUtils.touch(DEV_SINK_FILENAME)
            Hydro::FileSink.new(filename: DEV_SINK_FILENAME)
          end
        when "test"
          Hydro::MemorySink.new
        end
    end

    def hydro_client
      @hydro_client ||= Hydro::Client.new(environment: Rails.env)
    end

    def hydro_publisher
      @hydro_publisher ||= Hydro::Publisher.new(
        sink: hydro_sink,
        site: hydro_site,
        topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 },
      )
    end

    def hydro_consumer(options = {},
                       env = Rails.env)
      source = case env
               when "development"
                 if ENV["HYDRO_KAFKA_BROKERS"]
                   hydro_kafka_source(options, env)
                 else
                   FileUtils.touch(DEV_SINK_FILENAME)
                   File.truncate(DEV_SINK_FILENAME, 0)
                   Hydro::FileSource.new(**{ filename: DEV_SINK_FILENAME }.merge(options))
                 end
               when "test"
                 Hydro::MemorySource.new(**{ sink: hydro_sink }.merge(options))
               when "production"
                 hydro_kafka_source(options, env)
               end

      hydro_client.consumer(source: source, decode_failure_handler: decode_failure_handler)
    end

    def decode_failure_handler
      lambda do |message, error|
        Dependabot::Exceptions.push(
          "gh.hydro.msg.offset": message.offset,
          "gh.hydro.msg.partition": message.partition,
          "gh.hydro.msg.topic": message.topic,
          "gh.dependabot_api.hydro.failed_before_processing": true,
        )

        Dependabot::Exceptions.report(error)
      end
    end

    def hydro_kafka_source(options, env)
      seed_brokers = ENV["HYDRO_KAFKA_BROKERS"].to_s.split

      raise ArgumentError, "ENV['HYDRO_KAFKA_BROKERS'] not set!" if seed_brokers.none? && env == "production"

      Hydro::KafkaSource.new(**{
        seed_brokers: seed_brokers,
        client_id: ENV["KAFKA_CLIENT_ID"],
        ssl_ca_cert_file_path: ENV["HYDRO_KAFKA_CERT_PATH"],
      }.merge(options))
    end
  end

  extend HydroConfig

  at_exit do
    ActiveRecord::Base.connection_handler.clear_active_connections!(:all)
  end
end
