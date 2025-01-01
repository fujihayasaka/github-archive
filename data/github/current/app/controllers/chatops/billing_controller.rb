# typed: true
# frozen_string_literal: true

require "chatops-controller"

module Chatops
  class BillingController < ApplicationController
    include ::Chatops::Controller

    # CAP and verify_authenticity_token not required on chatops controllers
    # since these chatops are run by Hubbers from Slack and the routes for triggering them are only accessible through our internal network
    skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction
    skip_before_action :verify_authenticity_token

    chatops_namespace :billing
    chatops_help "Commands for working with billing engineering related tasks"

    depends_on_clusters ApplicationRecord::Mysql1,
      only: [:list]

    chatop :cpwu,
      /cpwu\s+(?<identifier>(enterprise|org|user|customer_id):[^\s]+)\s+(?<product>[^\s]+)\s+(?<sku>[^\s]+)(\s+(?<options>.+))?/,
      "cpwu [enterprise:slug|org:login|user:login|customer_id:id] <product> <sku> [repo_id:ID] [org_id:ID] [actor_id:ID] [quantity:NUMBER] - Can Proceed With Usage" do

      account_type, id = jsonrpc_params[:identifier].split(":")
      unless id.present?
        return chatop_send "Please provide a valid #{account_type} identifier enterprise:slug, org:login, user:login, or customer_id:id"
      end

      entity = nil
      customer_id = nil
      customer =
        case account_type
        when "enterprise"
          entity = Business.find_by(slug: id)
          entity&.customer
        when "org", "user"
          entity = User.find_by(login: id)
          entity&.customer
        when "customer_id"
          customer_id = id
          Customer.find_by(id: id)
        end
      customer_id = customer.id if customer_id.nil? && customer.present?

      if customer_id.blank?
        return chatop_send "Unable to imply customer ID from #{account_type} identifier: #{id}"
      end

      product = jsonrpc_params[:product]
      sku = jsonrpc_params[:sku]

      # Parse optional parameters if provided
      options = jsonrpc_params[:options] || ""
      options_hash = {}
      options.scan(/(\w+):(\S+)/).each do |key, value|
        options_hash[key] = value
      end

      repo_id = options_hash["repo_id"]
      org_id = options_hash["org_id"]
      actor_id = options_hash["actor_id"]
      quantity = options_hash["quantity"]

      cpwu_params = ::Billing::Platform::CanProceedWithUsage::RequestParams.new(
        customer_id: customer_id.to_s,
        product: product.to_s,
        sku: sku.to_s,
        repo_id: repo_id.presence.to_i,
        org_id: org_id.presence.to_i,
        actor_id: actor_id.presence.to_i,
        quantity: quantity.presence.to_f,
      )
      unless cpwu_params.valid?
        return chatop_send "Please provide value(s) for #{cpwu_params.missing_keys.to_sentence}"
      end

      # Make API calls
      cpwu_response = ::Billing::Platform::CanProceedWithUsage.call(cpwu_params)
      customer_response = ::Billing::Platform::Api::Client.new.get_customer(customer_id: customer_id.to_s)

      # Format the response
      response = []

      if entity
        response << "✅ Billable Entity: #{entity.display_login} (ID: #{entity.id})"
      end

      if customer.nil?
        response << "⚠️  Dotcom Customer #{customer_id} not found"
      else
        response << "✅ Dotcom Customer: #{customer.name} (ID: #{customer_id})"
        response << "\t- Billed via Billing Platform: #{customer.billed_via_billing_platform? ? "Yes" : "No"}"
      end

      if customer_response.is_a?(::Billing::Platform::Api::Error)
        response << "❌ Error getting customer details: #{customer_response.message}"
      else
        customer_data = customer_response[:customer]
        billing_target_icon = customer_data[:billingTarget] == :Azure ? ":azure:" : ":zuora:"
        response << "✅ Billing Platform Customer details retrieved successfully"
        response << "\t- Billing Target: #{billing_target_icon} #{customer_data[:billingTarget]}"
        response << "\t- Azure Subscription ID: #{customer_data[:azureAccountId]}" if customer_data[:azureAccountId].present?
        response << "\t- Zuora Account Number: #{customer_data[:zuoraAccountNumber]}" if customer_data[:zuoraAccountNumber].present?
        response << "\t- Has Zuora Subscription: #{customer_data[:hasZuoraSubscription] ? "Yes" : "No"}"
        response << "\t- Has Payment Method: #{customer_data[:hasPaymentMethod] ? "Yes" : "No"}"
      end

      if cpwu_response.error.present?
        response << "❌ Error checking 'canProceed': #{T.must(cpwu_response.error).message}"
      else
        response << "Can Proceed With Usage"
        response << (cpwu_response.can_proceed ? "✅ Usage CAN proceed" : "❌ Usage CANNOT proceed")

        pretty_json = JSON.pretty_generate(cpwu_response.serialize)
        response << "JSON Response\n"
        response << "```\n#{pretty_json}\n```"
      end

      chatop_send response.join("\n")
    end
  end
end
