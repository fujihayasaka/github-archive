# frozen_string_literal: true

TRACKED_CACHE_PATTERNS = {
  %r{update_job_logs/s3/\d+} => :update_job_logs_s3,
}.freeze

ActiveSupport::Notifications.subscribe("cache_read.active_support") do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  key = event.payload.fetch(:key)
  hit = event.payload.fetch(:hit) { false }

  TRACKED_CACHE_PATTERNS.each do |pattern, name|
    next unless pattern.match?(key.to_s)

    MetricsClient.increment("cache.#{name}", tags: { hit: hit })
    Dependabot::Logger.info(
      msg: "cache read",
      name: name,
      hit: hit,
      key: key,
    )
  end
end
