# typed: true
# frozen_string_literal: true

class Hook::Event::EnterpriseEvent < Hook::Event
  # Anonymous Git access is only available in GHES, not GitHub.com.
  supports_targets Business if GitHub.anonymous_git_access_available?

  display_name "Enterprise"
  description "Global anonymous access enabled, anonymous access disabled."

  event_attr :action, :actor_id, required: true

  def actor
    @actor ||= User.find(actor_id)
  end
end
