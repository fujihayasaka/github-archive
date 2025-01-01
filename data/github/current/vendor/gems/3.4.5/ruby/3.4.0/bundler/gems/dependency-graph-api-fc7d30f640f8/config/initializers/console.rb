require_relative "../../lib/hmac_authentication"

# Trilogy will close the connection on us when we do certain things like interrupt execution. This resets the connection so we can keep going
def reset_connection!
  ActiveRecord::Base.connection_pool.disconnect!
  "Connection reset. Happy hacking!"
end

# Issue a temprorary HMAC token
def give_me_hmac
  puts "Token will be valid for 10 minutes"
  key = ENV["DEPENDENCY_GRAPH_API_HMAC_KEYS"].to_s.split(" ").first.to_s
  HMACAuthentication.request_hmac(Time.now, key)
end

def add_console_appender
  SemanticLogger.add_appender(io: $stdout, formatter: :color) unless SemanticLogger.appenders.console_output?
end

# Log queries to STDOUT
def enable_query_logging
  add_console_appender
  RailsSemanticLogger::ActiveRecord::LogSubscriber.logger.level = :debug
end

# >> time { some_slow_method }
#     user     system      total        real
# 0.960000   0.020000   0.980000 (  0.990485)
def time(times = 1)
  require "benchmark"
  ret = nil
  Benchmark.bm { |x| x.report { times.times { ret = yield } } }
  ret
end

# Subscribe to ActiveSupport instrumentation and `puts` it.
def print_instrumentation(regex)
  ActiveSupport::Notifications.subscribe(regex) do |name, _, _, _, data|
    puts "#{name}: #{data.inspect}"
  end
end
