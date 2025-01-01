# typed: true
# frozen_string_literal: true
require "chatops-controller"
require "github_chatops_extensions"

module Chatops
  class OrgsController < ApplicationController
    include ::Chatops::Controller

    chatops_namespace :orgs
    chatops_help "Commands for getting information about GitHub organizations"
    chatops_error_response "More information is available [in Sentry](https://sentry.io/organizations/github/issues/). Try re-running the command or ask for help in [#octoshift](https://github.slack.com/archives/CV0E7204X)."

    depends_on_clusters ApplicationRecord::Mysql1,
      only: [:list]

    # Opt-out of all conditional access and secondary authn checks, since these chatops are run by Hubbers
    # from Slack and the routes for triggering them are only accessible through our internal network
    skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction


    private def verify_authenticity_token?
      false # robots do this
    end

    chatop :login,
           /login (?<id>\S+)/,
           "login <id> - get an organization's login (slug) based on its ID" do

      id = Integer(jsonrpc_params.require(:id), exception: false)

      if id.nil?
        chatop_send("Please provide an integer ID.")
        return
      end

      organization = Organization.find_by(id: id)

      if organization.nil?
        chatop_send("Organization does not exist.")
        return
      end

      chatop_send(organization.login)
      return
    end

    chatop :id,
           /id (?<login>\S+)/,
           "id <login> - get an organization's ID based on its login (slug)" do
      login = jsonrpc_params.require(:login)

      if login.nil?
        chatop_send("Please provide a login.")
        return
      end

      organization = Organization.find_by_login(login)

      if organization.nil?
        chatop_send("Organization does not exist.")
        return
      end

      chatop_send(organization.id)
      return
    end
  end
end
