require "hydro"
require "socket"

# Most of this code is a shameless grab of what's in gh/gh's `lib/github/config/hydro.rb`
# Anything additive to this script should be called out in a comment, because it might surprise us.
# Some things, like circuit breaking, brought in additional deps and were trimmed out instead.

DEVELOPMENT_BROKER = "127.0.0.1:9092"

if Rails.env.production?
  puts "Don't use this script in production!"
  exit
end

def hydro_metrics_namespace
  "github-#{Rails.env}"
end

def local_host_name
  Socket.gethostname
end

def hydro_kafka_sink(env = Rails.env, options = {})
  use_ssl = false
  seed_brokers = DEVELOPMENT_BROKER.split(",")

  Hydro::KafkaSink.new(
    **{
      seed_brokers: seed_brokers,
      client_id: "#{hydro_metrics_namespace}-#{local_host_name}",
      logger: DependencyGraph.logger,
    }.merge(options),
  )
end

def publish(payload, options = {})
  publisher = hydro_publisher
  result = publisher.publish(payload, **options)
  if !result.success?
    report_error(result.error, **options.slice(:schema))
  end
  # Customized from gh/gh: close immediately to guarantee flushing
  publisher.close
  result
end

def hydro_site
  return "localhost" unless Rails.env.production?
end

def hydro_sink(env = Rails.env)
  max_buffer_size = 1000
  max_queue_size = 5000

  kafka_sink = hydro_kafka_sink(env, {
    producer_options: {
      retry_backoff: 1,
      delivery_interval: 2,
      delivery_threshold: 1000,
      max_buffer_size: max_buffer_size,
      max_queue_size: max_queue_size,
      idempotent: false,
    },
  })

  # for easy debugging of what's getting published:
  Hydro::Sink.tee(kafka_sink, hydro_log_sink)
end

def hydro_log_sink
  logger = ::Logger.new(Rails.root.join("log/hydro-#{Rails.env}.log"))
  formatter = ->(message) {
    if message.data
      decoded = Hydro::Decoding::ProtobufDecoder.decode(message.data)
    end

    [
      "\e[36m[#{message.timestamp || Time.now}]\e[0m",
      "\e[35m#{message.schema}\e[0m",
      "\e[33m#{message.data&.bytesize} bytes\e[0m",
      "\e[37m#{decoded&.to_h.to_json}\e[0m",
    ].join(" ")
  }

  Hydro::LogSink.new(logger, formatter: formatter)
end

def hydro_encoder
  # Report schemas that populate `nil` for scalar fields.
  nil_scalar_handler = ->(error) do
    schema = error.schema.name.gsub(/:+/, ".").downcase.sub("hydro.schemas.", "")
    tags = [
      "schema:#{schema}",
      "field:#{error.field.name}",
    ]
  end

  Hydro::ProtobufEncoder.new(
    Hydro::Site.new(hydro_site),
    nil_scalar_handler: nil_scalar_handler,
  )
end

def hydro_publisher
  hydro_client = Hydro::Client.new(environment: Rails.env)
  hydro_client.publisher(
    sink: hydro_sink,
    site: hydro_site,
    encoder: hydro_encoder,
  )
end
