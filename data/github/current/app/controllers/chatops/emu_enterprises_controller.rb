# typed: false
# frozen_string_literal: true
require "chatops-controller"
require "github_chatops_extensions"

module Chatops
  class EmuEnterprisesController < ApplicationController
    include ::Chatops::Controller
    include ::GitHubChatopsExtensions::Checks::Includable::Room

    ALLOWED_ROOMS = ["#emu-ops"].freeze

    # Opt-out of all conditional access and secondary authn checks, since these chatops are run by Hubbers
    # from Slack and the routes for triggering them are only accessible through our internal network
    skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

    before_action :guard_chatop_with_ff, except: :list

    chatops_namespace :emus
    chatops_help "Commands for getting information about GitHub EMU Enterprises"
    chatops_error_response "More information is available [in Sentry](https://sentry.io/organizations/github/issues/).
    Try re-running the command or ask for help in [#external-identities](https://github.slack.com/archives/C013TTZFFC1)."

    depends_on_clusters ApplicationRecord::Mysql1,
      only: [:list]

    private def verify_authenticity_token?
      false # robots do this
    end

    private def guard_chatop_with_ff
      require_in_room(ALLOWED_ROOMS)
    end

    private def enterprises(value)
      short_code_business = Business.find_by(shortcode: value)
      slug_business = Business.find_by(slug: value)
      [short_code_business, slug_business].uniq.compact
    end

    private def format_message(enterprise)
      message = "Enterprise name: #{enterprise.name}\n"
      message += "EMU enabled?: #{enterprise.enterprise_managed_user_enabled?}\n"
      if enterprise.enterprise_managed_user_enabled?
        message += "EMU shortcode: #{enterprise.shortcode}\n"
      end
      message += "Enterprise slug: #{enterprise.slug}\n"
      message += "Enterprise organization(s): #{enterprise.organizations.join(", ")}\n\n"
      message
    end

    chatop :find,
           /find (?<value>\S+)/, # Store input parameter without whitespace to ID
           "find <value> - get information about an enterprise based on slug or short code" do

      value = jsonrpc_params.require(:value)

      if value.nil?
        chatop_send("Please provide a string.")
        return
      end

      found_enterprises = enterprises(value)
      if found_enterprises.empty?
        chatop_send("Enterprise does not exist.")
        return
      end

      chatops_message = ""
      found_enterprises.each do |enterprise|
        chatops_message += format_message(enterprise)
      end
      chatop_send(chatops_message)
      return
    end
  end
end
