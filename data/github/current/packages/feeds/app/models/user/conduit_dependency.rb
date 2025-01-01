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
    event = feed_items&.first
    event&.time&.to_time&.in_time_zone
  rescue Conduit::Client::Error
    nil
  end

  # Public: The last time the user has performed an action on orgs in a business that
  # generated a Conduit event.
  #
  # Returns ActiveSupport::TimeWithZone or nil
  def last_event_for_business_at(org_ids:)
    user_events = Conduit::Api::Feed.new(self, viewer: self, twirp_items: feed_items).build.items

    org_events = user_events.find do |event|
      org_ids.include?(event.repository&.owner&.id)
    end&.created_at
  rescue Conduit::Client::Error
    nil
  end

  # Public: Deletes events for that user in Conduit.
  def clear_events(public_only: false)
    GitHub.conduit_client.delete_resource_events(
      resource_type: "user",
      resource_id: T.unsafe(self).id,
      is_public_only: public_only
    )
  rescue Conduit::Client::Error
    nil
  end

  private

  def feed_items
    GitHub.conduit_client.get_user_events(viewer: self, user: self)[:items]
  end
end
