# typed: true
# frozen_string_literal: true

class HydroLoader
  def self.load_github
    return if GitHub.hydro_initialized?
    Hydro.consumer_logger = GitHub::Telemetry::Logs.lib_logger("Hydro", level: GitHub.environment.fetch("HYDRO_CONSUMER_LOG_LEVEL", "fatal"))
    Hydro.publisher_logger = if GitHub.single_or_multi_tenant_enterprise?
      GitHub::ThrottledLogger.new(GitHub::Telemetry::Logs.lib_logger("Hydro", level: GitHub.environment.fetch("HYDRO_PUBLISHER_LOG_LEVEL", "fatal")), delay: 10)
    else
      GitHub::Telemetry::Logs.lib_logger("Hydro", level: GitHub.environment.fetch("HYDRO_PUBLISHER_LOG_LEVEL", "fatal"))
    end

    Hydro.load_schemas(Rails.root.join("lib/hydro"))

    # Hydro sinks and publishers are initialized with their own instances of
    # Hydro::Instrumenter and their own Hydro::DatadogReporter subscribers in
    # order to include sink/publisher-specific tags. This serves as a backstop by
    # subscribing to the default ActiveSupport::Notifications instrumenter,
    # which will catch any events instrumented with the global default
    # instrumenter. We'll get the metrics but without specific tagging.
    Hydro::DatadogReporter.start(
      dogstatsd: -> { GitHub.dogstats },
      client_id: GitHub.hydro_metrics_namespace,
    )

    Dir["config/instrumentation/hydro/subscriptions/*.rb"].each do |file|
      require_relative "../#{file}"
    end

    GitHub.hydro_initialized = true
  end
end
