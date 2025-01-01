# typed: true
# frozen_string_literal: true

class Hook::Payload::InstallationTargetPayload < Hook::Payload
  def to_payload_hash
    {
      action: hook_event.action,
      target_type: target_type,
      account: account_hash,
    }.merge(changes_payload)
  end

  private

  def account_hash
    target = hook_event.target

    case hook_event.target
    when Business
      api_serialize(:business_hash, target)
    when Organization
      api_serialize(:organization_hash, target, { full: true })
    else
      api_serialize(:user_hash, target)
    end
  end

  def target_type
    case hook_event.target
    when Business
      "Business"
    when Organization
      "Organization"
    else
      "User"
    end
  end
end
