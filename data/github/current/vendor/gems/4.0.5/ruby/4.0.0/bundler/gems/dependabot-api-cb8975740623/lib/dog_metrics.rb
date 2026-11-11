# frozen_string_literal: true

require "resolv"
require "datadog/statsd"

class DogMetrics
  include Singleton

  %i(count distribution gauge histogram timing).each do |method_name|
    define_method method_name do |stat, v, tags: {}|
      dogstats.send(method_name, stat, v, tags: dogtags(tags))
      dogstats.flush(sync: true)
    end
  end

  def increment(stat, tags: {})
    dogstats.increment(stat, tags: dogtags(tags))
    dogstats.flush(sync: true)
  end

  def time(stat, tags: {}, &block)
    val = dogstats.time(stat, tags: dogtags(tags), &block)
    dogstats.flush(sync: true)
    val
  end

  def distribution_time(key, tags: {})
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
  ensure
    distribution(key, duration(start), tags: tags)
  end

  def close
    if dogstats
      dogstats.flush(sync: true)
      dogstats.close
    end

    @dogstats = nil
  end

  def dogtags(hash_or_array)
    # aqueduct_rails passes tags already formatted for dogstats, so just return
    return hash_or_array if hash_or_array.instance_of?(Array)

    hash_or_array.map { |k, v| v.nil? ? nil : "#{k}:#{v}" }.compact
  end

  def host
    Resolv.getaddress(ENV["DOGSTATSD_HOST"] || "127.0.0.1").freeze
  end

  def port
    ENV["DOGSTATSD_PORT"]&.to_i || 28125
  end

  private

  def monotonic_time
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def duration(start, ending = nil)
    ending ||= case start
               when Float
                 monotonic_time
               else
                 Time.current
               end

    ((ending - start) * 1_000).round
  end

  def dogstats
    @dogstats ||= create_connection
  end

  def create_connection
    Datadog::Statsd.new(
      host, port,
      logger: Rails.logger,
      namespace: "dependabot-api",
      tags: dogtags(application: "dependabot-api"),
    )
  end
end
