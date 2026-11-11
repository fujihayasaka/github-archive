# typed: true
# frozen_string_literal: true

module GlobalEvents
  module Repository
    # Emitted after a repository has been removed.
    #
    # The event payload will include:
    #  repository_id - the ID of the repository which was removed
    REMOVED = "global_events.repository.removed"
  end
end
