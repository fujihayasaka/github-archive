# typed: true
# frozen_string_literal: true

class Hook::Payload::PagePayload < Hook::Payload
  def to_payload_hash
    {}.tap do |payload|
      payload[:action] = hook_event.action
      payload[:page] = api_serialize(:page_hash, hook_event.page)
      # This is silly - we likely will never have a nil html_url outside of tests, and the OpenAPI spec requires it to
      # be present, but the model doesn't guarantee it.
      payload[:page][:html_url] ||= ""

      # the event payload gets updated_at, because page objects don't have the
      # property. We only put it on updated events because, well, that's what it
      # says on the tin.
      payload[:updated_at] = hook_event.triggered_at&.to_time.utc.xmlschema if hook_event.action.to_s == "updated"
    end.merge(changes_payload)
  end
end
