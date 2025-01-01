require "fake_dog_statsd"

config     = Rails.application.config_for(:dogstatsd)
host, port = config.fetch(:host), config.fetch(:port)

DependencyGraph.logger.debug "=== Capturing stats on #{host}:#{port} ==="

class LoggingOutput
  @has_issued_suppression_warning = false

  def <<(stat)
    return if truthy_env("HIDE_ALL_STATS")
    if truthy_env("HIDE_ALL_NON_DG_API_STATS", default: true) && !stat.include?("dependency_graph")
      if !@has_issued_suppression_warning
        DependencyGraph.logger.debug "=== Non dg-api rails output has been suppressed. Check dogstatsd_script.rb for more details ==="
        @has_issued_suppression_warning = true
      end
      return
    end

    DependencyGraph.logger.debug("[dogstatsd] #{stat}")
  end

  def truthy_env(env_var_name, default: false)
    value = ENV.fetch(env_var_name, nil)
    return default if value.nil?
    return value.downcase == "true" || value == "1"
  end
end

FakeDogStatsd.run(
  host:   host,
  port:   port,
  output: LoggingOutput.new,
)
