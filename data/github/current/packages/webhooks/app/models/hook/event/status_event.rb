# typed: true
# frozen_string_literal: true

class Hook::Event::StatusEvent < Hook::Event
  supports_targets *DEFAULT_TARGETS
  description "Commit status updated from the API."

  event_attr :status, required: true

  def target_repository
    status.repository
  end

  def actor
    status.creator
  end
end
