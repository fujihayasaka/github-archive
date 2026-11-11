# typed: true
# frozen_string_literal: true

require "monolith-twirp-support-nexus"

module Api::Internal::Twirp::Support
  module Nexus
    module V1
      # Provides access to Support-relevant data.
      class UsersAPIHandler < Api::Internal::Twirp::Handler

        handles_service(MonolithTwirp::Support::Nexus::V1::UsersAPIService)

        allow_access_for :user, :client, allowed_clients: %w(nexus).freeze

        # Public: Implementation of the GetRefundEligibility Twirp RPC.
        # Accepts a GetRefundEligibilityRequest and returns an array of GetRefundEligibilityResponse
        def get_refund_eligibility(req, env)
          user_id = id_argument(req.user_id, env[:user_id])
          unless user_id
            return Twirp::Error.invalid_argument("must be non-empty", argument: "user_id")
          end
          user = User.find_by(id: user_id)
          if user.nil?
            return Twirp::Error.not_found("user does not exist", argument: "user_id")
          end

          if req.products.empty?
            return Twirp::Error.invalid_argument("no products specified", argument: "products")
          end

          results = req.products.map do |product|
            case product
            when "copilot_individual" # This includes Copilot Pro and Copilot Pro Plus
              user.help_hub_eligibility.helphub_copilot_refund_eligibility
            else
              return Twirp::Error.invalid_argument("invalid product in #{req.products}", argument: "products")
            end
          end

          { results: }
        end

        # Public: Refund and cancel a subscription item
        # subscription_item_id - the id of Billing::SubscriptionItem to refund and cancel
        # returns RefundSubscriptionItemResponse hash
        def refund_subscription_item(req, env)
          subscription_item_id = id_argument(req.subscription_item_id, env[:subscription_item_id])
          unless subscription_item_id
            return Twirp::Error.invalid_argument("must be non-empty", argument: "subscription_item_id")
          end
          subscription_item = Billing::SubscriptionItem.find_by(id: subscription_item_id)
          if subscription_item.nil?
            return Twirp::Error.not_found("subscription_item does not exist", argument: "subscription_item_id")
          end
          copilot_product = subscription_item.subscribable
          if copilot_product.nil?
            return Twirp::Error.not_found("subscribable product does not exist", argument: "subscription_item_id")
          end
          account = subscription_item.user
          if account.nil?
            return Twirp::Error.not_found("account not found", argument: "subscription_item_id")
          end
          full_refund = subscription_item.created_at.after?(31.days.ago)

          Audit.context.push(support_context: "helphub refund_copilot_individual")
          result = Billing::Public::SubscriptionItem.cancel_and_refund(product: copilot_product, account: account, full_refund: full_refund)
          {
            submitted: result.ok?
          }
        end
      end
    end
  end
end
