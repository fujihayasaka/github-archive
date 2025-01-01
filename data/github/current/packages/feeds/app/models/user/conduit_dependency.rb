# typed: true
# frozen_string_literal: true

module User::ConduitDependency
  extend ActiveSupport::Concern
  include GitHub::Memoizer

  # Public: The last time the user has performed an action within GitHub that
  # generated a Conduit event.
  #
  # Returns ActiveSupport::TimeWithZone or nil
  memoize def last_conduit_event_at
    event = GitHub.conduit_client.get_user_events(viewer: self, user: self)[:items]&.first
    event&.time&.to_time&.in_time_zone
  rescue Conduit::Client::Error
    nil
  end
end
