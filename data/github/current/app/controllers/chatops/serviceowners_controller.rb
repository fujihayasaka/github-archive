# typed: true
# frozen_string_literal: true

require "chatops-controller"
require "serviceowners"

class Chatops::ServiceownersController < ApplicationController
  include ::Chatops::Controller

  GITHUB_URL = /\Ahttps\:\/\/github.com\/github\/github\/blob\/\w+\//

  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  chatops_namespace :serviceowners
  chatops_help "Get the service owner for a monolith file with `.serviceowners for path`."
  chatops_error_response "Try re-running the command or ask for help in [#eng-maintainership](https://github-grid.enterprise.slack.com/archives/CGYKZBE07)."

  depends_on_clusters ApplicationRecord::Mysql1, only: [:list]

  private def verify_authenticity_token?
    false # robots do this
  end

  memoize def serviceowners # rubocop:disable GitHub/UseRestfulActions
    Serviceowners::Main.new
  end

  chatop :for,
  /for (?<input>.*)?/,
  "for \<path\> - Get the service owner for a monolith file." do

    if jsonrpc_params.require(:input).nil?
      chatop_send("Please provide a path.")
      return
    end

    input = jsonrpc_params.require(:input).gsub(GITHUB_URL, "")
    input = input.start_with?("/") ? input[1..-1] : input

    sentence = "The file `#{input}` "

    if (service = serviceowners.spec_for_path(input)&.service).present?
      sentence += "belongs to the [#{service.name}](https://catalog.githubapp.com/services/github/#{service.name}) service.\n"

      if service.teams.any?
        sentence += "Team name(s): #{service.teams.map { |t| "[#{t.name}](https://github.com/orgs/github/teams/#{t.name})" }.join(", ")}.\n"
        sentence += "Slack channel(s): #{service.teams.map { |t| "##{t.slack}" }.join(", ")}.\n"
      end
    else
      sentence += "is unowned."
    end

    chatop_send(sentence)
  end
end
