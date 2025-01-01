# typed: false
# frozen_string_literal: true

module Stratocaster::Filters
  # Filters a list of events for org all timeline based on if user has
  # permission to see events. Persmission is granted by being the given user
  # included in in the list of team_members for the event.
  #
  # events - Array of Stratocaster::Event items to filter in place
  class TeamMembersFilter < BaseFilter
    def self.apply(events, viewer)
      events.delete_if do |event|
        !event.team_members.include?(viewer.id)
      end
    end

    # Finds the current Organization Team members at the time the Event was
    # dispatched.
    #
    # Returns an Array of Integer User IDs.
    def self.team_members_for(event)
      return unless event.org_record

      team_info = event.payload["team"] || event.payload[:team]
      team_id = team_info && (team_info["id"] || team_info[:id])
      user_ids = Set.new

      if repo = event.repo_record
        if team_id
          # If the event is about a repo and a team (like adding a repo to a
          # team), dispatch to all members of that team and all org admins.
          user_ids += event.org_record.admins.pluck(:id)

          if team = Team.find_by_id(team_id)
            user_ids += team.member_ids
          end
        else
          # If the event is just about a repo (like a push to a repo), dispatch
          # to every org member with access to the repo.
          org_reader_ids = Set.new(event.org_record.member_ids)
          org_reader_ids &= repo.actor_ids(type: User) if repo.private?

          user_ids += org_reader_ids
        end
      elsif team_id
        if event.payload[:notify_owners]
          # If the event is about a team, dispatch to org admins if specified
          user_ids += event.org_record.admins.pluck(:id)
        elsif team = Team.find_by_id(team_id)
          # If the event is about a team, dispatch to all members of that team.
          user_ids += team.member_ids
        end
      elsif (event.payload[:membership_id] || event.payload["membership_id"]).to_i > 0
        # From early days we stored `membership_id` information in the payload (which
        # was the `id` for an instance of the once viable `TeamMember` class), but until around
        # 2011-11 we didn't not store additional team information.  We cannot resolve the
        # team references now, but these shouldn't be dispatched again anyway.
        # See: https://github.com/github/github/pull/25183 for more background.
        raise "Attempting to re-dispatch an ancient Event with insufficient team membership information."
      else
        # Dispatch to all members of the org.
        user_ids += event.org_record.people_ids
      end

      user_ids.to_a
    end
  end
end
