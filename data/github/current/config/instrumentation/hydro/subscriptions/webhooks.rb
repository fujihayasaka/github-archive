# typed: true
# frozen_string_literal: true

Hydro::EventForwarder.configure(source: GlobalInstrumenter) do
  subscribe("webhook.delivery_metadata") do |payload|
    hook, hook_event, hook_payload, hook_custom_delivery = payload.values_at(:hook, :hook_event, :hook_payload, :hook_custom_delivery)

    message = ActiveRecord::Base.connected_to(role: :reading) do
      {
        delivery_guid: hook_payload[:guid],
        delivery_type: hook_custom_delivery ? hook_custom_delivery : :HOOKSHOT,
        github_request_id: payload[:request_id],
        hook_id: hook.id,
        hook_url: payload[:safe_hook_url],
        hook_event: hook_event.event_type,
        hook_action: hook_event.try(:action),
        hook_actor: serializer.user(hook_event.actor),
        hook_installation_target_type: hook.installation_target_type.underscore.upcase.gsub("/", "_").to_sym,
        hook_installation_target_id: hook.installation_target_id,
        hook_creator: serializer.user(hook.creator),
        hook_oauth_application: serializer.app(hook.oauth_application),
        hook_payload_bytes: hook_payload.to_json(dangerously_allow_all_keys: true).bytesize,
        hook_target_repository: serializer.repository(hook_event.target_repository),
        hook_target_organization: serializer.organization(hook_event.target_organization),
        hook_integration_installation_id: hook_payload.dig(:payload, :installation, :id),
        job_id: payload[:job_id],
        queue: payload[:queue],
        kube_cluster: GitHub.kubernetes_cluster_name,
      }
    end

    publish(message, schema: "github.webhooks.v0.DeliveryMetadata", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("webhook.dropped_event_metadata") do |payload|
    message = ActiveRecord::Base.connected_to(role: :reading) do
      {
        event_type: payload[:event_type],
        event_action: payload[:event_action],
        filtered_reason: payload[:filtered_reason],
        guid: payload[:guid],
        target_repository_id: payload[:target_repository_id],
        target_organization_id: payload[:target_organization_id],
        triggered_at: payload[:triggered_at],
        request_id: payload[:request_id],
        kube_cluster: GitHub.kubernetes_cluster_name,
      }
    end

    publish(message, schema: "github.webhooks.v0.DroppedEventMetadata")
  end

  subscribe("webhook.dropped_delivery_metadata") do |payload|
    message = ActiveRecord::Base.connected_to(role: :reading) do
      {
        guid: payload[:guid],
        event_type: payload[:event_type],
        event_action: payload[:event_action],
        dropped_reason: payload[:dropped_reason],
        hook_id: payload[:hook_id],
        delivery_type: payload[:delivery_type],
        target_repository_id: payload[:target_repository_id],
        target_organization_id: payload[:target_organization_id],
        request_id: payload[:request_id],
        triggered_at: payload[:triggered_at],
        parent: payload[:parent],
        kube_cluster: GitHub.kubernetes_cluster_name,
      }
    end

    publish(message, schema: "github.webhooks.v0.DroppedDeliveryMetadata")
  end
end
