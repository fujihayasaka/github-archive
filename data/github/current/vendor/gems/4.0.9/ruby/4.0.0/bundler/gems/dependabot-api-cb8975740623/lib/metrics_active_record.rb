# frozen_string_literal: true

ActiveSupport::Notifications.subscribe("sql.active_record") do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)

  MetricsClient.timing("db_query.time", event.duration)
  MetricsClient.increment("db_query.count")
end
