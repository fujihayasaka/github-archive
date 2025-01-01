# typed: true
# frozen_string_literal: true

module Api::Internal::Twirp::Support
  module HelpHub
    module V1
      module UsedProductsDependency
        BILLING_ORG_LIMIT = 25
        ACTIONS_REPO_LIMIT = 25

        sig { params(user: ::User, product_name: String).returns(T::Boolean) }
        def has_product_usage?(user, product_name)
          return true if billing_usage?(user, product_name)

          product_specific_usage?(user, product_name) || false
        end

        # Look for billing usage on the user's account or any organization they belong to
        sig { params(user: ::User, product_name: String).returns(T::Boolean) }
        def billing_usage?(user, product_name)
          dogstats_time("user_billing_usage") { user_billing_usage?(user, product_name) } ||
          dogstats_time("organization_billing_usage") { organization_billing_usage?(user, product_name) }
        end

        # Specific product usage cases
        sig { params(user: ::User, product_name: String).returns(T::Boolean) }
        def product_specific_usage?(user, product_name)
          case product_name
          when "actions"
            # Check if the user has any public repositories with actions workflow runs
            dogstats_time("actions_public_repositories") do
              user.public_repositories.limit(100).any? { |repo| repo.workflow_runs.any? }
            end
          else
            false
          end
        end

        # Look for usage in any organization the user is a member of
        sig { params(user: ::User, product_name: String).returns(T::Boolean) }
        def organization_billing_usage?(user, product_name)
          orgs = user.organizations.limit(BILLING_ORG_LIMIT)
          GitHub.dogstats.histogram("twirp.helphub_used_products.billing_usage_org_count", orgs.count)

          orgs.any? do |organization|
            usage_checker = usage_checker(organization, product_name)
            usage_results = usage_checker.usage_results_for(product: product_name).compact

            # Organizations that delegate billing to a business check account_consumed_quantity
            if organization.delegate_billing_to_business?
              usage_results.any? { |usage| usage.account_consumed_quantity.to_i > 0 }
            else
              usage_results.any? { |usage| usage.entitlement_raw_quantity_consumed.to_i > 0 }
            end
          end
        end

        # Look for usage on the user's account
        sig { params(user: ::User, product_name: String).returns(T::Boolean) }
        def user_billing_usage?(user, product_name)
          usage_checker = usage_checker(user, product_name)
          entitlements = usage_checker.entitlements_for(name: product_name.capitalize)
          return false if entitlements&.consumed_quantity.nil?

          entitlements.consumed_quantity.positive?
        end

        sig { params(account: ::User, product_name: String).returns(Billing::UsageChecker) }
        def usage_checker(account, product_name)
          Billing::UsageChecker.new(
            account: account,
            product_names: [product_name],
            timeout: 5
          )
        end

        private

        sig { params(action_name: String).returns(T.untyped) }
        def dogstats_time(action_name)
          GitHub.dogstats.time("twirp.helphub_used_products.#{action_name}") { yield }
        end
      end
    end
  end
end
