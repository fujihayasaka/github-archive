# typed: true
# frozen_string_literal: true

module Team::SizeDependency
  extend T::Helpers
  requires_ancestor { Team }

  # Public: Determine whether the number of unique members across a team and all
  # of its subteams exceeds a given threhsold.
  #
  # Enables UI to require confirmation before pinging a large number of users
  # (e.g., when requesting reviews to a team)
  #
  # threshold - number of users allowed (above that, the team is considered "large")
  #
  # Returns true if the member count exceeds the threshold.
  def large?(threshold:)
    member_ids = Set.new # Avoids counting same person in multiple teams twice
    team_queue = [self]
    while team = team_queue.shift
      team_queue.push(*team.child_teams)
      member_ids.merge(team.member_ids)
      # Stop counting if team is confirmed to be large
      # (so worst case is 100 checks, not O(teams) or O(members))
      return true if member_ids.size > threshold
    end
    false
  end
end
