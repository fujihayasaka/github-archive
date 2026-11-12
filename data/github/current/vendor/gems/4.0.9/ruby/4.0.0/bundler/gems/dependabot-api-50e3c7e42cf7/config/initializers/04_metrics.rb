# frozen_string_literal: true

# We test these metrics, so want them active in the test env too
require "metrics_active_record"
require "metrics_cache_hits"

if Rails.env.production?
  require "metrics_middleware"
  require "metrics_active_job"

  if Dependabot.enterprise?
    require "enterprise_metrics"
    MetricsClient = EnterpriseMetrics.instance

    require "kafka/statsd"
    Kafka::Statsd.namespace = "dependabot_api.kafka"
    Kafka::Statsd.host      = MetricsClient.host
    Kafka::Statsd.port      = MetricsClient.port

  else
    require "dog_metrics"
    MetricsClient = DogMetrics.instance

    require "kafka/datadog"
    Kafka::Datadog.namespace = "dependabot_api.kafka"
    Kafka::Datadog.host      = MetricsClient.host
    Kafka::Datadog.port      = MetricsClient.port
  end

  # HTTP server metrics via Rack middleware
  Rails.application.middleware.insert(
    0,
    MetricsMiddleware,
    client: MetricsClient,
  )

else
  class FakeMetricsClient
    def host
      # No-op
    end

    def port
      # No-op
    end

    %i(count distribution gauge histogram timing).each do |method_name|
      define_method method_name do |stat, v, tags: {}|
        # No-op
      end
    end

    def increment(stat, tags: {})
      # No-op
    end

    def time(*_args)
      yield if block_given?
    end

    def distribution_time(*_args)
      yield if block_given?
    end

    def close
      # No-op
    end
  end

  MetricsClient = FakeMetricsClient.new
end
