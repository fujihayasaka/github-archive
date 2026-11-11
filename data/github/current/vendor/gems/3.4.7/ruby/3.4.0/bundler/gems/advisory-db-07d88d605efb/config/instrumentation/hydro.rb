# frozen_string_literal: true

ActiveSupport::Notifications.subscribe("publish.publisher.hydro") do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  schema = event.payload.fetch(:schema)
  topic = event.payload.fetch(:topic)

  AdvisoryDB.stats.increment("hydro.publish", {
    tags: AdvisoryDB.dogtags(schema: schema, topic: topic),
  })
end
