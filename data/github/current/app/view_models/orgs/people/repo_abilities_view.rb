# typed: true
# frozen_string_literal: true

class Orgs::People::RepoAbilitiesView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  attr_reader :abilities
  attr_reader :action
  attr_reader :active
  attr_reader :person
  attr_reader :repository

  def show_teams_divider?
    team_abilities.any?
  end

  def teams_divider_access_type
    abilities.first.action.to_s
  end

  def collaborator_ability
    return @collaborator_ability if defined? @collaborator_ability

    @collaborator_ability = abilities.detect { |a| a.actor_type == "User" }
  end

  def organization_ability
    @organization_ability ||= abilities.detect { |a| a.actor_type == "Organization" }
  end

  def team_abilities
    @team_abilities ||= abilities.select { |a| a.actor_type == "Team" }.sort_by(&:action).reverse
  end

  def show_public_repo_notice?
    repository.public? && action == :read
  end

end
