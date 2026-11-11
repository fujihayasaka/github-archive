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

        connected_to_writing_for :suspend_user

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

        # Public: Implementation of the GetUserInfo Twirp RPC.
        # Returns support-relevant information about a GitHub user for nexus
        # ticket enrichment and DSA compliance checks.
        # Accepts user_id (preferred) or email (fallback). When looked up by
        # email, email_verified and email_is_primary indicate whether the
        # matched email is verified and whether it is the user's primary email.
        def get_user_info(req, env)
          user = resolve_user(req, env)
          return user if user.is_a?(Twirp::Error)

          lookup_email = req.respond_to?(:email) ? req.email.presence : nil
          primary_email = user.primary_user_email
          email_info = resolve_email_info(user, lookup_email, primary_email)

          {
            login: string_value(user.login),
            email: string_value(email_info[:email]),
            email_verified: bool_value(email_info[:verified]),
            email_is_primary: bool_value(email_info[:is_primary]),
            billing_plan: string_value(user.plan.name),
            highest_github_plan: string_value(resolve_highest_plan(user)),
            support_plan: string_value(resolve_support_plan(user)),
            account_type: string_value(resolve_account_type(user)),
            country_code: string_value(resolve_country_code(user)),
            copilot_plan: string_value(resolve_copilot_plan(user)),
          }
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

        # Public: Implementation of the SuspendUser Twirp RPC.
        # Suspends a GitHub user account for account takeover or abuse cases.
        def suspend_user(req, env)
          user_id = id_argument(req.user_id, env[:user_id])
          unless user_id
            return Twirp::Error.invalid_argument("must be non-empty", argument: "user_id")
          end

          reason = req.respond_to?(:reason) ? req.reason : nil
          if reason.blank?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "reason")
          end

          user = User.find_by(id: user_id)
          if user.nil?
            return Twirp::Error.not_found("user does not exist", argument: "user_id")
          end

          if user.suspended?
            { suspended: true, already_suspended: true }
          else
            Audit.context.push(support_context: "nexus suspend_user")

            notes = req.respond_to?(:notes) ? req.notes : nil
            success = user.suspend(reason, notes: notes)

            if success
              { suspended: true, already_suspended: false }
            else
              Twirp::Error.failed_precondition(user.errors[:base].join(", "))
            end
          end
        end

        private

        def string_value(value)
          Google::Protobuf::StringValue.new(value: value.to_s)
        end

        def bool_value(value)
          Google::Protobuf::BoolValue.new(value: value)
        end

        # Resolve user by user_id (preferred) or email (fallback).
        # Returns a User with eager-loaded associations or a Twirp::Error.
        def resolve_user(req, env)
          user_id = id_argument(req.user_id, env[:user_id])
          if user_id
            user = User.includes(:primary_user_email, :emails, :customer, :business_user_accounts)
              .find_by(id: user_id)
            return Twirp::Error.not_found("user does not exist", argument: "user_id") if user.nil?
            return user
          end

          email = req.respond_to?(:email) ? req.email : nil
          if email.present?
            user = User.find_by_email(email)
            return Twirp::Error.not_found("user does not exist", argument: "email") if user.nil?
            # Re-fetch with eager-loaded associations
            return User.includes(:primary_user_email, :emails, :customer, :business_user_accounts)
              .find_by(id: user.id)
          end

          Twirp::Error.invalid_argument("must provide user_id or email", argument: "user_id")
        end

        def resolve_country_code(user)
          customer = user.customer
          return "" if customer.nil?
          contact = customer.billing_contact
          contact.country_code.to_s
        end

        def resolve_copilot_plan(user)
          Copilot::User.new(user).copilot_plan.to_s
        end

        # When looked up by email, check that specific email's status.
        # When looked up by user_id, return the primary email's status.
        def resolve_email_info(user, lookup_email, primary_email)
          if lookup_email.present?
            matched = user.emails.find { |e| e.email.downcase == lookup_email.downcase }
            {
              email: lookup_email,
              verified: matched&.verified? == true,
              is_primary: matched.present? && primary_email.present? && matched.email.downcase == primary_email.email.downcase,
            }
          else
            {
              email: primary_email&.email.to_s,
              verified: primary_email&.verified? == true,
              is_primary: true,
            }
          end
        end

        def resolve_support_plan(user)
          business = user.enterprise_managed_business
          business ||= user.business_user_accounts.first&.business
          business&.calculated_support_plan.to_s
        end

        # Returns the highest plan name across the user's enterprise account, orgs, and personal plan.
        def resolve_highest_plan(user)
          return user.plan.name.to_s if user.organization?

          business = user.enterprise_managed_business
          business ||= user.business_user_accounts.first&.business
          business_plan = business&.plan
          return business_plan.name.to_s if business_plan

          enterprise_org = user.organizations.find { |org| org.plan&.enterprise? }
          return enterprise_org.plan.name.to_s if enterprise_org

          business_org = user.organizations.find { |org| org.plan&.business? }
          return business_org.plan.name.to_s if business_org

          user.plan.name.to_s
        end

        def resolve_account_type(user)
          if user.is_enterprise_managed?
            "ENTERPRISE"
          elsif user.organization?
            "ORGANIZATION"
          else
            "INDIVIDUAL"
          end
        end
      end
    end
  end
end
