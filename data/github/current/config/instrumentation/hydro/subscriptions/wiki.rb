# typed: true
# frozen_string_literal: true

# This is a Hydro event subscription related to wiki push/edit via web UI or Git.

Hydro::EventForwarder.configure(source: GlobalInstrumenter) do
  subscribe("wiki.create") do |payload|
    wiki_content = [payload[:page_name], payload[:page_body]].compact.join(" ")

    message = {
      actor: serializer.user(payload[:actor]),
      page_body: payload[:page_body],
      page_name: payload[:page_name],
      page_url: payload[:page_url],
      repository: serializer.repository(payload[:repository]),
      request_context: serializer.request_context(GitHub.context.to_hash),
      spamurai_form_signals: serializer.spamurai_form_signals(GitHub.context[:spamurai_form_signals]),
      repository_owner: serializer.repository_owner(payload[:repository]),
      actor_is_member: serializer.user_repository_member?(payload[:repository], payload[:actor]),
      page_body_size: serializer.string_bytesize(payload[:page_body]),
      specimen_wiki_content: serializer.specimen_data(wiki_content),
    }

    publish(message, schema: "github.v1.WikiCreate")
  end

  subscribe("wiki.update") do |payload|
    wiki_content = [payload[:page_name], payload[:page_body]].compact.join(" ")

    message = {
      actor: serializer.user(payload[:actor]),
      page_body: payload[:page_body],
      page_name: payload[:page_name],
      page_url: payload[:page_url],
      repository: serializer.repository(payload[:repository]),
      request_context: serializer.request_context(GitHub.context.to_hash),
      spamurai_form_signals: serializer.spamurai_form_signals(GitHub.context[:spamurai_form_signals]),
      repository_owner: serializer.repository_owner(payload[:repository]),
      actor_is_member: serializer.user_repository_member?(payload[:repository], payload[:actor]),
      page_body_size: serializer.string_bytesize(payload[:page_body]),
      specimen_wiki_content: serializer.specimen_data(wiki_content),
    }

    publish(message, schema: "github.v1.WikiUpdate", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("wiki.edit") do |payload|
    ref_updates = payload[:ref_updates].map do |(ref, before, after)|
      {
        ref_name: ref&.dup&.force_encoding(Encoding::UTF_8),
        previous_ref_oid: before,
        current_ref_oid: after,
      }
    end
    message = {
      pusher: serializer.user(payload[:pusher]),
      owner: serializer.user(payload[:owner]),
      request_context: payload[:request_context],
      repository: serializer.repository(payload[:repository]),
      wiki_world_writable: payload[:wiki_world_writable],
      ref_updates: Array.wrap(ref_updates),
      feature_flags: payload[:feature_flags],
      pushed_at: payload[:pushed_at],
      business_id: payload[:business_id],
    }

    publish(message, schema: "github.v1.WikiPostReceive")
  end
end
