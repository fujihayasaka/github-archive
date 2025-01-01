# typed: true
# frozen_string_literal: true

require "chatops-controller"

class Chatops::CodeowningTeamController < ApplicationController
  include ::Chatops::Controller

  STAFF_REPOSITORIES = %w[github github-ui heaven copilot-api]

  LoginNotAssociatedWithHubberError = Class.new(StandardError)
  NoTeamsAssociatedWithHubberError = Class.new(StandardError)

  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  chatops_namespace :codeowning_team
  chatops_help "Get the code-owning team(s) that a Hubber belongs to with `.codeowning_team for hubber-login`."
  chatops_error_response "Try re-running the command or ask for help in [#meao](https://github-grid.enterprise.slack.com/archives/CFC9WQ53Q)."

  depends_on_clusters ApplicationRecord::Mysql1, only: [:list]

  private def verify_authenticity_token?
    false # robots do this
  end

  chatop :for,
  /for (?<input>.*)?/,
  "for <login> - Get the code-owning team that a hubber belongs to." do

    input = jsonrpc_params.require(:input)
    success = false
    begin
      all_github_teams_for_hubber = get_all_teams_for_hubber(input)
      codeowning_teams = get_all_codeowning_teams
      intersecting_teams = codeowning_teams & all_github_teams_for_hubber

      if intersecting_teams.empty?
        sentence = "Hubber #{input} does not belong to any codeowning teams in the #{STAFF_REPOSITORIES.join(", ")} repositories that are visible to you."
      else
        team_names = intersecting_teams.join(", ")
        sentence = "Hubber #{input} belongs to the following codeowning #{'team'.pluralize(intersecting_teams.size)}: #{team_names}."
        success = true
      end
      rescue LoginNotAssociatedWithHubberError, NoTeamsAssociatedWithHubberError => error
        sentence = error.message
    end

    if success
      GitHub.dogstats.increment("chatops.codeowning_team.successful_request")
    else
      GitHub.dogstats.increment("chatops.codeowning_team.failed_request")
    end
    chatop_send(sentence)
  end

  private

  def get_all_teams_for_hubber(login)
    caller = User.find_by(login: params[:user])
    user = User.find_by(login: login)
    unless user&.employee?
      raise LoginNotAssociatedWithHubberError.new("Login #{login} is not associated with a Hubber.")
    end

    github_org = Organization.find_by!(login: "github")
    visible_github_teams_for_caller = github_org.visible_teams_for(caller)
    teams_that_hubber_belongs_to = user.teams.where(organization_id: github_org.id)
    all_teams = visible_github_teams_for_caller.where(id: teams_that_hubber_belongs_to.ids)
    if all_teams.empty?
      raise NoTeamsAssociatedWithHubberError.new("Hubber #{login} does not belong to any teams in the GitHub org that are visible to you.")
    else
      all_teams.pluck(:name).map { |team| team.downcase.gsub(" ", "-") }
    end
  end

  def get_all_codeowning_teams
    all_teams = Set.new

    STAFF_REPOSITORIES.each do |repo_name|
      repository = Repository.find_by(owner_login: "github", name: repo_name)
      next unless repository
      codeowners_file = Repository::Codeowners.new(repository).file.contents
      repo_teams = extract_teams_from_codeowners_file(codeowners_file)
      all_teams.merge(repo_teams)
    end

    all_teams
  end

  def extract_teams_from_codeowners_file(file)
    teams = Set.new

    file.each_line do |line|
      next if line.starts_with?("#")
      split_line = line.split("@github/")
      # Logic below deals with the scenario where multiple teams
      # own the same file. The first element will contain the name
      # of the file, all elements beyond that should be a team name
      split_line[1..].each do |team|
        team_name = team&.strip
        teams.add(team_name) if team_name
      end
    end

    teams
  end
end
