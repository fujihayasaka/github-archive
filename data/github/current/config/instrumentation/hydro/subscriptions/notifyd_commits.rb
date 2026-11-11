# typed: true
# frozen_string_literal: true

require "notifyd-client"

Hydro::EventForwarder.configure(source: GlobalInstrumenter) do
  subscribe("commit_comment.create") do |payload|
    commit_comment = payload[:commit_comment]
    actor = payload[:actor]
    next unless commit_comment && actor
    next if commit_comment.importing?

    Notifyd::NotifyPublisher.new.async_publish(
      actor_id: actor.id,
      subject_id: commit_comment.id,
      subject_klass: commit_comment.class.name,
      context: {
        actor_id: actor.id,
        operation: "create",
      }
    )
  end

  subscribe("commit_comment.update") do |payload|
    commit_comment = payload[:commit_comment]
    actor = payload[:actor]
    next unless commit_comment && actor
    previous_body = payload[:previous_body]
    next unless previous_body

    Notifyd::NotifyPublisher.new.async_publish(
      actor_id: actor.id,
      subject_id: commit_comment.id,
      subject_klass: commit_comment.class.name,
      context: {
        operation: "update",
        actor_id: actor.id,
        previous_body: previous_body,
        current_body: commit_comment.body,
      }
    )
  end
end
