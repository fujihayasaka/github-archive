# typed: true
# frozen_string_literal: true

# These are Hydro event subscriptions related to Loops.

Hydro::EventForwarder.configure(source: GlobalInstrumenter) do
  subscribe("loop.create") do |payload|
    loop = payload[:loop]
    next unless loop.is_a?(::Loops::Loop)

    actor = payload[:actor]
    serialized_actor = serializer.user(actor)
    owner = nil
    if (id = loop.owner_id)
      # Avoid extra DB call if the owner is the actor
      owner = actor if actor.is_a?(User) && actor.id == id
      owner ||= begin
        User.find(id)
      rescue ActiveRecord::RecordNotFound
        nil
      end
    end

    title_string = [loop.title, loop.description].compact.join("\n")
    nodes_payload = loop.respond_to?(:nodes) && loop.nodes ? loop.nodes : []

    user_generated_content_msg = {
      request_context: serializer.request_context(GitHub.context.to_hash),
      spamurai_form_signals: serializer.spamurai_form_signals(GitHub.context[:spamurai_form_signals]),
      action_type: :CREATE,
      content_type: :LOOP,
      actor: serialized_actor,
      content_url: Hydro::EntitySerializer.url_for_model(loop),
      content_created_at: loop.updated_at,
      title: serializer.specimen_data(title_string),
      content: serializer.specimen_data(nodes_payload.to_json),
      owner: owner ? serializer.user(owner) : nil,
      content_visibility: loop.visibility == "public" ? :PUBLIC : :PRIVATE,
      content_global_relay_id: Platform::Helpers::GlobalId.for(loop, user_preference: false, user_opt_out: false),
    }

    publish(user_generated_content_msg,
      schema: "github.platform_health.v1.UserGeneratedContent",
      topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 } # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
    )
  end

  subscribe("loop.update") do |payload|
    loop = payload[:loop]
    next unless loop.is_a?(::Loops::Loop)

    actor = payload[:actor]
    serialized_actor = serializer.user(actor)
    owner = nil
    if (id = loop.owner_id)
      owner = actor if actor.is_a?(User) && actor.id == id
      owner ||= begin
        User.find(id)
      rescue ActiveRecord::RecordNotFound
        nil
      end
    end

    title_string = [loop.title, loop.description].compact.join("\n")
    nodes_payload = loop.respond_to?(:nodes) && loop.nodes ? loop.nodes : []

    user_generated_content_msg = {
      request_context: serializer.request_context(GitHub.context.to_hash),
      spamurai_form_signals: serializer.spamurai_form_signals(GitHub.context[:spamurai_form_signals]),
      action_type: :UPDATE,
      content_type: :LOOP,
      actor: serialized_actor,
      content_url: Hydro::EntitySerializer.url_for_model(loop),
      content_created_at: loop.updated_at,
      title: serializer.specimen_data(title_string),
      content: serializer.specimen_data(nodes_payload.to_json),
      owner: owner ? serializer.user(owner) : nil,
      content_visibility: loop.visibility == "public" ? :PUBLIC : :PRIVATE,
      content_global_relay_id: Platform::Helpers::GlobalId.for(loop, user_preference: false, user_opt_out: false),
    }

    publish(user_generated_content_msg,
      schema: "github.platform_health.v1.UserGeneratedContent",
      topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 } # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
    )
  end
end
