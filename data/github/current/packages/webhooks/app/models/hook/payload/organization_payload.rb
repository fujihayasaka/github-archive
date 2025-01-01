# typed: true
# frozen_string_literal: true

class Hook::Payload::OrganizationPayload < Hook::Payload
  def to_payload_hash
    org     = hook_event.organization
    user    = hook_event.user
    action  = hook_event.action

    result = {}.tap do |hash|
      hash[:action] = action

      if :member_invited == action.to_sym
        hash[:invitation] = api_serialize(:invitation_hash, hook_event.invitation)
        hash[:user] = api_serialize(:user_hash, user) if user
      elsif [:member_added, :member_removed].include?(action.to_sym)
        hash[:membership] = api_serialize(:org_membership_hash, org, user: user, full: false)
      end
    end

    result.merge(changes_payload)
  end
end
