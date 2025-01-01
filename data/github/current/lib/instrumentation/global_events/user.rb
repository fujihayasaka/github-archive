# typed: true
# frozen_string_literal: true

module GlobalEvents
  module User
    # Emitted when a user's access to a repository *may* have changed. This
    # could be in response to any number of actions: removed as a collaborator,
    # removed from a team, removed from an org, etc.
    #
    # The event payload will include:
    #  user           - the User whose access may have changed
    #  repository_ids - the Array of Repository IDs that may have been affected
    REPOSITORY_ACCESS_CHANGED = "global_events.user.repository_access_changed"
  end
end
