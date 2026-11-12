# frozen_string_literal: true

Rails.configuration.after_initialize do
  require_relative "../instrumentation"

  if Rails.env.development?
    # temporary hack until github-telemetry-ruby supports smarter appending
    provider = GitHub::Telemetry::Logs::IOStreamProvider.new
    SemanticLogger.appenders.clear
    SemanticLogger.add_appender(io: provider.stream, formatter: :color, level: :debug)
  end
end
