# typed: true
# frozen_string_literal: true

module Chatops
  class CustomerController < ApplicationController
    include ::Chatops::Controller

    chatops_namespace :customer
    chatops_help "Commands for getting information about GitHub customers"
    chatops_error_response "Try re-running the command or ask for help in [#billing-engineering](https://github-grid.enterprise.slack.com/archives/C04K3MLN1QE)."

    depends_on_clusters ApplicationRecord::Mysql1,
      only: [:list]

    # Opt-out of all conditional access and secondary authn checks, since these chatops are run by Hubbers
    # from Slack and the routes for triggering them are only accessible through our internal network
    skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

    private def verify_authenticity_token?
      false # robots do this
    end

    chatop :id,
           /id (?<login>\S+) (?<entity_type>user|org|business)/,
           "id <login> <entity_type> - get the customer ID based on the login (slug) and entity type (user, org, business)" do
      login = jsonrpc_params.require(:login)
      entity_type = jsonrpc_params.require(:entity_type)

      entity = case entity_type
      when "user"
        User.find_by(login: login)
      when "org"
        Organization.find_by(login: login)
      when "business"
        Business.find_by(slug: login)
      end

      if entity.nil?
        chatop_send("Entity does not exist.")
        return
      end

      customer = entity.customer

      if customer.nil?
        chatop_send("Customer does not exist.")
        return
      end

      chatop_send(customer.id)
      return
    end

    chatop :login,
           /login (?<id>\S+)/,
           "login <id> - get the customer's login based on the customer id" do
      id = jsonrpc_params.require(:id)

      if id.nil?
        chatop_send("Please provide an id.")
        return
      end

      customer = Customer.find_by(id: id)

      if customer.nil?
        chatop_send("Customer does not exist.")
        return
      end

      billable_owner = customer.billable_owner
      name = billable_owner&.name

      chatop_send(name)
      return
    end
  end
end
