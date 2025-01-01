# typed: true
# frozen_string_literal: true

require "notifyd-client"

Hydro::EventForwarder.configure(source: GlobalInstrumenter) do
  subscribe("gist_comment.create") do |payload|
    gist_comment = payload[:gist_comment]
    actor = payload[:actor]
    next unless gist_comment && actor
    next unless GitHub::flipper[:notifyd_enable_gist_events_for_actor].enabled?(actor)

    Notifyd::NotifyPublisher.new.async_publish(
      actor_id: actor.id,
      subject_id: gist_comment.id,
      subject_klass: gist_comment.class.name,
      context: {
        actor_login: actor.display_login,
        actor_id: actor.id,
        operation: "create",
        current_body: gist_comment.body,
      }
    )
  end

  subscribe("gist_comment.update") do |payload|
    gist_comment = payload[:gist_comment]
    actor = gist_comment.user
    next unless gist_comment && actor
    next unless GitHub::flipper[:notifyd_enable_gist_events_for_actor].enabled?(actor)
    previous_body = payload[:previous_body]
    next unless previous_body

    Notifyd::NotifyPublisher.new.async_publish(
      actor_id: actor.id,
      subject_id: gist_comment.id,
      subject_klass: gist_comment.class.name,
      context: {
        operation: "update",
        actor_login: actor.display_login,
        actor_id: actor.id,
        previous_body: previous_body,
        current_body: gist_comment.body,
      }
    )
  end
end
