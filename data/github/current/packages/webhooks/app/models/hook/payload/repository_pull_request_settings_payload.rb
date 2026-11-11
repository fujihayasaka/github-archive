# typed: true
# frozen_string_literal: true

class Hook::Payload::RepositoryPullRequestSettingsPayload < Hook::Payload
  delegate :action, to: :hook_event

  def to_payload_hash
    {
      action:,
      changes:
    }
  end

  private

  def changes
    hook_event.changes
  end
end
