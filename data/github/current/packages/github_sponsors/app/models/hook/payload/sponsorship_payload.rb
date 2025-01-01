# typed: true
# frozen_string_literal: true

class Hook::Payload::SponsorshipPayload < Hook::Payload
  include Formatter

  delegate :action, :sponsorship, :current_tier, :previous_tier, :pending_change_tier, :pending_change_on,
    to: :hook_event

  delegate :sponsor, :sponsorable,
    to: :sponsorship

  def to_payload_hash
    {
      action: action,
      sponsorship: {
        node_id: sponsorship.global_relay_id,
        created_at: time(sponsorship.created_at),
        # We encourage webhook consumers to use the `sponsorable` field, but
        # we must maintain the `maintainer` field to avoid breaking changes
        # See https://github.com/github/sponsors/issues/1141
        sponsorable: serialized_sponsorable,
        maintainer: serialized_sponsorable,
        sponsor: serialized_sponsor,
        privacy_level: sponsorship.privacy_level,
        tier: api_serialize(:sponsors_tier_hash, pending_change_tier || current_tier),
      },
    }.tap do |payload|
      payload[:changes] = changes if changes
      payload[:effective_date] = time(pending_change_on.to_datetime) if pending_change_on
    end
  end

  private

  def serialized_sponsorable
    if sponsorable.organization?
      api_serialize(:organization_hash, sponsorable)
    else
      api_serialize(:user_hash, sponsorable)
    end
  end

  def serialized_sponsor
    if sponsor.organization?
      api_serialize(:organization_hash, sponsor)
    else
      api_serialize(:user_hash, sponsor)
    end
  end

  def changes
    return unless hook_event.changes || serialized_from_tier

    Hash(hook_event.changes).tap do |result|
      result[:tier] = { from: serialized_from_tier } if serialized_from_tier
    end
  end

  def serialized_from_tier
    if pending_change_tier
      api_serialize(:sponsors_tier_hash, current_tier)
    elsif previous_tier
      api_serialize(:sponsors_tier_hash, previous_tier)
    end
  end
end
