# frozen_string_literal: true

ActiveSupport::Notifications.subscribe("fetch_rate_limit.github_throttle") do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  rate_limit = event.payload.fetch(:rate_limit)

  AdvisoryDB.stats.gauge("github_throttle.limit", rate_limit.limit)
  AdvisoryDB.stats.gauge("github_throttle.interval", rate_limit.interval)
end

ActiveSupport::Notifications.subscribe("print_ticket.github_throttle") do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  ticket = event.payload.fetch(:ticket)

  GitHub::Telemetry::Logs.logger.debug { "github_throttle.ticket.printed: #{ticket}" }
  AdvisoryDB.stats.increment("github_throttle.ticket.printed")
end

ActiveSupport::Notifications.subscribe("take_ticket.github_throttle") do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  timeout = event.payload.fetch(:timeout)
  ticket = event.payload[:ticket]
  age = ticket ? Time.current - ticket.to_f : nil
  tags = AdvisoryDB.dogtags(timeout: timeout)

  GitHub::Telemetry::Logs.logger.debug { "github_throttle.ticket.taken: #{ticket}" } if ticket
  AdvisoryDB.stats.timing("github_throttle.ticket.taken", event.duration, tags: tags)
  AdvisoryDB.stats.timing("github_throttle.ticket.age", age, tags: tags) if age
end
