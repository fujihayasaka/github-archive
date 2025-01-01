# typed: false
# frozen_string_literal: true

module Stratocaster::Filters
  class ConditionalAccessFilter < BaseFilter
    # Filters a list of events to exclude events created in the context of
    # organizations that require additional authentication for conditional
    # access policies.
    #
    # https://github.com/github/authorization/blob/main/docs/cap/update-callsite-to-cap-filtering.md
    #
    # events - Array of Stratocaster::Event items to filter
    #
    # Returns Array of Stratocaster::Event items
    def self.apply(events, viewer)
      filter = ConditionalAccess::Model::Filter.new(
        self,
        actor: viewer,
        web_session: user_session,
        remote_ip: remote_ip,
        location: :model,
      )

      # With Stratocaster, its possible that references stored on the Event
      # have been deleted. (See: https://github.com/github/github/pull/166442#issuecomment-754064346).
      # This filters Events that no longer have a TFCA.
      existing_tfca_ids = Stratocaster::Event.
        target_for_conditional_access_records(events).
        pluck(:id)
      events.delete_if do |event|
        !existing_tfca_ids.include?(event.target_for_conditional_access_id)
      end

      filter.authorized_resources(events)
    end

    def self.user_session
      actor_session = GitHub.context[:actor_session]
      UserSession.find_by_id(actor_session)
    end

    def self.remote_ip
      GitHub.context[:actor_ip]
    end
  end
end
