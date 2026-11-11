# typed: true
# frozen_string_literal: true

module Organizations
  class Teams::ReviewAssignmentFormComponent < ApplicationComponent
    attr_reader :team

    def initialize(team:)
      @team = team
    end

    # Limit for number of delegates available to select in the UI.
    # Should be less than or equal to db limit- check review_request_delegation.db
    DELEGATE_SELECTION_LIMIT = Team::ReviewRequestDelegation::DELEGATE_LIMIT - 3

    def routing_algorithm
      team.review_request_delegation_algorithm
    end

    memoize def current_team_member_count
      team.review_request_delegation_member_count || 1
    end

    def never_assign_team_members
      if team.review_request_delegation_include_child_team_members
        team.members_scope
      else
        team.members
      end
    end

    memoize def any_excluded_team_members?
      team.review_request_delegation_excluded_members.size > 0
    end

    memoize def selected_ids
      team.review_request_delegation_excluded_members.pluck(:user_id)
    end

    def member_selected?(member)
      selected_ids.include?(member.id)
    end

    # Controls number of delegates available for users to select in the UI for reviewing PRs.
    def select_times
      (1..DELEGATE_SELECTION_LIMIT)
    end

    def selected?(element, value)
      element == value
    end

    def include_child_team_members_checked?
      team.review_request_delegation_include_child_team_members ? "checked" : ""
    end

    def count_members_already_requested_checked?
      team.review_request_delegation_count_members_already_requested ? "checked" : ""
    end

    def remove_team_request_checked?
      team.review_request_delegation_remove_team_request ? "checked" : ""
    end
  end
end
