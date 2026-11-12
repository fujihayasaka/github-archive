# frozen_string_literal: true

ActiveSupport::Notifications.subscribe("process_action.action_controller") do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)

  controller =
    if event.payload[:controller]
      # Clean up the controller; convert "Namespace::ResourcesController"
      # into "namespace_resources".
      memo = event.payload[:controller].underscore
      memo.tr!("/", "_")
      memo.delete_suffix!("_controller")
      memo
    else
      "unknown"
    end
  action = event.payload[:action] || "unknown"
  format = event.payload[:format] || "unknown"
  method = event.payload[:method] || "unknown"
  status = event.payload[:status] || "unknown"
  status_range =
    if event.payload[:status]
      # Add the status_range tag by converting a 422 status into a "4xx" range.
      "#{event.payload[:status] / 100}xx"
    else
      "unknown"
    end

  tags = AdvisoryDB.dogtags(
    controller: controller,
    action: action,
    format: format,
    method: method,
    status: status,
    status_range: status_range,
  )

  AdvisoryDB.stats.batch do
    AdvisoryDB.stats.distribution("request.dist.time", event.duration, tags: tags)
    AdvisoryDB.stats.distribution("request.dist.cpu_time", event.cpu_time, tags: tags)
    AdvisoryDB.stats.distribution("request.dist.idle_time", event.idle_time, tags: tags)

    db_time, view_time = event.payload.values_at(:db_runtime, :view_runtime)
    AdvisoryDB.stats.distribution("request.dist.db_time", db_time, tags: tags) if db_time
    AdvisoryDB.stats.distribution("request.dist.view_time", view_time, tags: tags) if view_time
  end
end
