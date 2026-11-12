# typed: strict
# frozen_string_literal: true

module OctoCore::Telemetry::Stats

  # A Stats implementation that sends metrics to Datadog.
  class Datadog
    extend T::Sig
    extend T::Helpers

    include OctoCore::Telemetry::Stats

    class Env < OctoCore::Env::Base
      define_env_variable :datadog_host, :string, required: true, default: "localhost"
      define_env_variable :datadog_port, :string, required: true, default: "8125"
      define_env_variable :datadog_namespace, :string, required: true, default: OctoCore::AppEnvironment.app_name
      define_env_variable :datadog_env, :string, required: true, default: OctoCore::AppEnvironment.env
    end

    sig { params(host: String, port: String, namespace: String, env: String).void }
    def initialize(
      host: Env.datadog_host,
      port: Env.datadog_port,
      namespace: Env.datadog_namespace,
      env: Env.datadog_env
    )
      @dd = T.let(::Datadog::Statsd.new(host, port, tags: ["service:#{namespace}", "env:#{env}"]), ::Datadog::Statsd)
    end

    sig { override.params(stat: String, count: Numeric, tags: T::Array[String]).void }
    def count(stat, count, tags = EMPTY_TAGS)
      @dd.count(stat, count, tags: tags)
    end

    sig { override.params(stat: String, tags: T::Array[String]).void }
    def increment(stat, tags = EMPTY_TAGS)
      @dd.increment(stat, tags: tags)
    end

    sig { override.params(stat: String, value: Numeric, tags: T::Array[String]).void }
    def gauge(stat, value, tags = EMPTY_TAGS)
      @dd.gauge(stat, value, tags: tags)
    end

    sig { override.params(stat: String, value: Numeric, tags: T::Array[String]).void }
    def distribution(stat, value, tags = EMPTY_TAGS)
      @dd.distribution(stat, value, tags:)
    end
  end
end
