# typed: true
# frozen_string_literal: true

class Hook::Payload::AutolinkPayload < Hook::Payload
  # The payload defined as a Ruby hash. Our event instance is available
  # as `hook_event`.
  #
  # In addition to any keys defined here, The `target_repository`,
  # `target_organization`, and `actor` from the event will be mixed in as
  # `repository`, `organization`, and `sender` respectively.
  def to_payload_hash
    {
      action: hook_event.action,
      autolink: api_serialize(:autolink_hash, hook_event.autolink).tap do |autolink|
        autolink[:updated_at] = hook_event.attributes[:triggered_at].iso8601 unless hook_event.attributes[:triggered_at].nil?
      end,
    }
  end
end
