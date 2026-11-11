# typed: strict
# frozen_string_literal: true

# Generates payload for secret scanning public monitoring alert webhook events.
# See Hook::Event::SecretScanningPublicMonitoringAlertEvent
class Hook::Payload::SecretScanningPublicMonitoringAlertPayload < Hook::Payload
  sig { returns(T::Hash[Symbol, T.untyped]) }
  def to_payload_hash
    event = T.let(hook_event, Hook::Event::SecretScanningPublicMonitoringAlertEvent)
    repo = Repository.find_by(id: event.repository_id)

    user = event.secret_author_id ? User.find_by(id: event.secret_author_id) : nil

    attribution = {
      committer_email: event.committer_email,
      method: SecretScanning::PublicMonitoringAlert.display_attribution_method(event.attribution_method.to_s),
    }
    attribution[:secret_author] = api_serialize(:simple_user_hash, user) if user

    if event.location && repo
      options = Api::SerializerOptions.fill({ serialize_login: :display, use_public_api_url: true })
      location_detail = Api::Serializer.secret_scanning_alert_location_from_object( # rubocop:disable GitHub/AlwaysUseApiSerializerSerialize
        event.location, repo, options
      )
      if location_detail
        attribution[location_detail[:type].to_sym] = location_detail[:details]
      end
    end

    {
      action: event.action,
      alert: {
        id: event.public_monitoring_alert_id.to_i,
        secret_type: event.slug,
        secret_type_display_name: event.label,
        created_at: Api::Serializer.time(event.created_at),
        repository: repo ? api_serialize(:simple_repository_hash, repo) : nil,
        attribution: attribution,
      },
    }
  end
end
