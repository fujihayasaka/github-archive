# typed: false
# frozen_string_literal: true

module Repos::AccessManagementDependency
  ADD_TEAMS_OR_PEOPLE = "Add teams or people"
  ADD_A_COLLABORATOR = "Add a collaborator"

  def search_field_hint
    return "Search by username, full name, or email" unless repository.in_organization?

    case add_type&.to_sym
    when :user
      "Search by username, full name, or email"
    when :team
      "Search by team name"
    else
      "Search by team name, username, full name, or email"
    end
  end

  def add_search_placeholder
    return "Find a team" if add_type&.to_sym == :team

    "Find people"
  end

  def is_user_fork_of_private_org_repo?
    repository.fork? && repository.in_organization? && repository.owner.user?
  end

  def add_user_label
    "Add people"
  end

  def add_team_label
    "Add teams"
  end

  def add_access_label
    return ADD_A_COLLABORATOR unless repository.in_organization?
    case add_type&.to_sym
    when :user
      add_user_label
    when :team
      add_team_label
    else
      ADD_TEAMS_OR_PEOPLE
    end
  end

  def select_member_message
    return "Select a collaborator above" unless repository.in_organization?

    case add_type&.to_sym
    when :user
      "Select a member above"
    when :team
      "Select a team above"
    else
      "Select a team or member above"
    end
  end
end
