# typed: strict
# frozen_string_literal: true

require "chatops-controller"

module Chatops
  class GitcoinController < ApplicationController
    include ::Chatops::Controller

    HELP_MESSAGE = <<~HEREDOC
      Gitcoin commands:
      .gitcoin help
      .gitcoin issue <title>
    HEREDOC

    # Opt-out of all conditional access and secondary authn checks, since these chatops are run by Hubbers
    # from Slack and the routes for triggering them are only accessible through our internal network.
    skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

    chatops_namespace :gitcoin
    chatops_help "Commands for working with gitcoin (billing team) stuff"
    chatops_error_response "More information is available [in Sentry](https://sentry.io/organizations/github/issues/)"

    depends_on_clusters ApplicationRecord::Mysql1,
      only: [:list]

    chatop :help,
           /help/,
           "help - displays list of available gitcoin chatops" do

      chatop_send HELP_MESSAGE
    end

    chatop :issue,
           /issue(?<title>.+)?/,
           "issue <title> - Create a new gitcoin issue" do

      if jsonrpc_params[:title].nil?
        chatop_send("Missing title for new gitcoin issue")
        return
      end

      title = jsonrpc_params[:title].strip
      message_id = jsonrpc_params[:message_id] || params[:message_id]
      if message_id.nil?
        chatop_send("Hubot failed to locate discussion (missing message_id).")
        return
      end

      user = params[:user]
      room_id = params[:room_id].delete_prefix("#")
      room_url = "https://github.slack.com/archives/#{room_id}"
      thread_url = "#{room_url}/p#{message_id}"
      body = "Created by @#{user} from [this Slack thread](#{thread_url}) in [##{room_id}](#{room_url})"

      new_issue = Billing::OpenGitcoinIssue.create(title, body)
      unless new_issue
        chatop_send("Failed to create new gitcoin issue")
        return
      end

      success_message = <<~HEREDOC
        Your new gitcoin issue has been freshly minted: #{new_issue.url}
        Thank you for your request 🙇
      HEREDOC

      chatop_send success_message
    end

    private

    sig { returns(T::Boolean) }
    def verify_authenticity_token?
      false # robots do this
    end
  end
end
