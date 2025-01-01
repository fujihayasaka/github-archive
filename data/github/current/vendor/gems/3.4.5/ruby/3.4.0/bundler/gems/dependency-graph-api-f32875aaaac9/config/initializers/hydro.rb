require "hydro"
require "hydro/datadog_reporter"

unless Rails.env.development?
  Hydro.instrumenter = ActiveSupport::Notifications

  Hydro::DatadogReporter.start({
    dogstatsd: Rails.application.stats,
    client_id: ENV.fetch("KAFKA_CLIENT_ID", "dependency_graph")
  })
end

HYDRO = Rails.application.config_for :hydro
