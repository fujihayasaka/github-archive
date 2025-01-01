# typed: true
# frozen_string_literal: true
# A hook fired when an organization blocks a user
class Hook::Event::OrgBlockEvent < Hook::Event
  supports_targets Organization, Business, Integration if GitHub.user_abuse_mitigation_enabled?
  description "A user has been blocked or unblocked."
  event_attr :org_id, :actor_id, :blocked_user_id, :action, required: true

  def target_organization
    @org ||= Organization.find_by(id: org_id)
  end

  def blocked_user
    @blocked_user ||= User.find_by(id: blocked_user_id)
  end

  def actor
    @actor ||= User.find_by(id: actor_id)
  end
end
