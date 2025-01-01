# typed: true
# frozen_string_literal: true

require "monolith-twirp-support-helphub"

module Api::Internal::Twirp::Support
  module HelpHub
    module V1
      # Provides access to business data.
      class BusinessesAPIHandler < Api::Internal::Twirp::Handler
        handles_service(MonolithTwirp::Support::HelpHub::V1::BusinessesAPIService)

        allow_access_for :user, :client, allowed_clients: %w(helphub).freeze

        GET_BUSINESSES_HARD_LIMIT = 100
        EXPIRED_EA_LIMIT = 14.days

        # NOTE: This RPC call is used to populate the enterprise accounts list
        # Public: Implementation of the GetBusinesses Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Support::HelpHub::V1::GetBusinessesRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response data, a list of businesses, suitable for use in a
        # MonolithTwirp::Support::HelpHub::V1::GetBusinessesResponse.
        def get_businesses(req, env)
          business_ids = req.business_ids
          user_id = id_argument(req.user_id)

          case
          when business_ids.present? && user_id.present?
            return Twirp::Error.invalid_argument("one must be non-empty", arguments: "business_ids, user_id")
          when business_ids.present?
            scope_or_error = businesses_for_business_ids(business_ids)
          when user_id.present?
            scope_or_error = businesses_for_user_id(user_id)
          else
            return Twirp::Error.invalid_argument("one must be non-empty", arguments: "business_ids, user_id")
          end

          if scope_or_error.is_a?(Twirp::Error)
            scope_or_error
          elsif scope_or_error.is_a?(Hash)
            { businesses: scope_or_error.flat_map { |role, businesses| build_business_list(businesses, admin_role: role.to_s) } }
          else
            { businesses: build_business_list(scope_or_error) }
          end
        end

        # Public: Implementation of the GetPremiumEntitlees Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Support::HelpHub::V1::GetPremiumEntitleesRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response data, a list of premium support businesses and the logins of
        # the support entitled users in the business.
        def get_premium_entitlees(req, env)
          offset = req.offset
          return Twirp::Error.invalid_argument("offset must be non-empty", arguments: "offset") unless offset

          premium_business_ids = Configuration::Entry
            .where(name: "support_plan", target_type: "Business").where("value LIKE ?", "premium%")
            .or(Configuration::Entry.where(name: "microsoft_support_plan", target_type: "Business").where.not(value: nil))
            .limit(GET_BUSINESSES_HARD_LIMIT)
            .offset(offset)
            .map(&:target_id)

          businesses = premium_business_ids.map do |id|
            if business = Business.find_by(id: id)
              entitled_logins = Set.new(business.owners.map(&:login) + business.billing_managers.map(&:login) + business.support_entitlees.map(&:login)).to_a
              {
                id: business.id,
                slug: business.slug,
                support_plan: business.calculated_support_plan,
                support_entitled_logins: entitled_logins
              }
            else
              { id: id, slug: "", support_plan: "", support_entitled_logins: [] }
            end
          end

          { businesses: businesses }
        end

        private

        # Private: Convert an array of business ids into Business objects.
        #
        # business_ids - The array of business ids.
        #
        # Returns a scope of Business objects or a Twirp::Error
        def businesses_for_business_ids(business_ids, limit = GET_BUSINESSES_HARD_LIMIT)
          if business_ids.size > limit
            return Twirp::Error.invalid_argument("must have a length <= #{limit}", argument: "business_ids")
          end

          Business.where(id: business_ids.to_a)
        end

        # Private: Convert an user id into Business objects.
        #
        # user_id - The user id.
        #
        # Returns a hash of Business objects by role or a Twirp::Error
        def businesses_for_user_id(user_id)
          user = User.find_by(id: user_id)
          if user.nil?
            return Twirp::Error.invalid_argument("does not exist", argument: "user_id")
          end

          owner_businesses = user.businesses(membership_type: :admin)
          owner_businesses_ids = owner_businesses.map(&:id)
          billing_manager_businesses = user.businesses(membership_type: :billing_manager)
            .reject { |b| b.id.in?(owner_businesses_ids) }
          billing_manager_businesses_ids = billing_manager_businesses.map(&:id)
          support_entitled_businesses = user.businesses(membership_type: :support_entitled)
            .reject { |b| b.id.in?(owner_businesses_ids) }
            .reject { |b| b.id.in?(billing_manager_businesses_ids) }

          {
            owner: owner_businesses,
            billing_manager: billing_manager_businesses,
            support_entitled: support_entitled_businesses,
          }
        end

        # Private: Convert an array of EnterpriseInstallation objects to the shape a Twirp response expects.
        #
        # enterprise_installations - The array of EnterpriseInstallation objects.
        #
        # Returns an array of Hash objects with installation data that matches the EnterpriseInstallationsListItem Twirp definition.
        def build_enterprise_installations(enterprise_installations)
          enterprise_installations.map do |installation|
            {
              id: installation.id,
              host_name: installation.host_name,
              created_at: Google::Protobuf::Timestamp.new(seconds: installation.created_at.to_i),
              license_hash: Digest::SHA256.base64digest(installation.license_hash),
              customer_name: installation.customer_name,
              version: installation.version
            }
          end
        end

        # Private: Convert an array of GitHub::EnterpriseWeb::License objects to the shape a Twirp response expects.
        #
        # business - A business object.
        #
        # Returns an array of Hash objects with business data that matches the EnterpriseInstallationsListItem Twirp definition.
        def build_enterprise_server_licenses(business)
          return [] unless business.enterprise_web_business_id.present?
          licenses = GitHub::EnterpriseWeb::License.all(business.enterprise_web_business_id).sort_by(&:expires_at)
          licenses.map do |license|
            {
              id: license.id,
              created_at: protobuf_timestamp_if_present(license.created_at),
              updated_at: protobuf_timestamp_if_present(license.updated_at),
              starts_at: protobuf_timestamp_if_present(license.starts_at),
              expires_at: Google::Protobuf::Timestamp.new(seconds: license.expires_at.to_time.to_i),
              seats: license.seats,
              checksum: license.checksum,
              type: license.type,
              state: license.state,
              is_advanced_security_enabled: license.advanced_security_enabled?
            }
          end
        rescue Faraday::Error => e
          Failbot.report(e)
          []
        end

        # Private: Check if the business has enabled Codespaces.
        #
        # business - A business object.
        #
        # Returns a boolean.
        def enabled_codespaces?(business)
          codespaces_business = Codespaces::BusinessDelegator.new(business)
          !codespaces_business.codespaces_disabled?
        end

        # Private: Check if the business has purchased Copilot.
        #
        # business - A business object.
        #
        # Returns a boolean.
        def purchased_copilot?(business)
          business.copilot_licensing_enabled? || Copilot::Business.new(business).total_cost > 0
        end

        # Private: Check if the business has purchased GHAS.
        #
        # business - A business object.
        #
        # Returns a boolean.
        def enabled_ghas?(business, licenses)
          if licenses.empty?
            business.advanced_security_purchased?
          else
            licenses.any? { |license| license[:is_advanced_security_enabled] }
          end
        end

        # Private: Check if the business has a GHES license.
        #
        # business - A business object.
        #
        # Returns a boolean.
        #
        # TODO: Add support for metered GHES licenses
        def has_ghes_license?(business)
          business.enterprise_web_business_id.present?
        end

        # Private: Check if the business has purchased enterprise licenses.
        #
        # business - A business object.
        #
        # Returns a boolean.
        def purchased_enterprise_license?(business)
          business.purchased_enterprise_licenses > 0
        end

        # Private: Get the billing details from the customer.
        #
        # business - A business object.
        #
        # Returns a hash with the billing details.
        def customer_billing_details(business)
          return {} unless business.billed_via_billing_platform?

          billing_client = ::Billing::Platform::Api::Client.new
          customer_response = billing_client.get_customer(customer_id: business&.customer.id)
          customer_response[:customer] || {}
        end

        # Private: Get the list of products that the business has purchased.
        #
        # business - A business object.
        # customer_details - A hash containing the customers billing details.
        #
        # Returns an array of strings with the products that the business has purchased.
        def purchased_products(business, licenses, customer_details)
          products = []
          if business.billed_via_billing_platform?
            enabled_products = customer_details[:enabledProducts]
            products.concat(enabled_products) if enabled_products.is_a?(Array)
          else
            products << "copilot" if purchased_copilot?(business)
            products << "codespaces" if enabled_codespaces?(business)
            products << "ghas" if enabled_ghas?(business, licenses)
            products << "ghec" if purchased_enterprise_license?(business)
          end
          products << "ghes" if has_ghes_license?(business)
          products
        end

        # Private: Get the billing target from the customer.
        #
        # customer_details - A hash containing the customers billing details.
        #
        # Returns a string with the billing target.
        def billing_target(customer_details)
          customer_details[:billingTarget] || ""
        end

        # Private: Convert an array of Business objects to the shape Twirp responses expect.
        #
        # businesses - The array of Business objects.
        # admin_role - the role ("owner"/"billing_manager"/"support_entitled"/"") for the related user
        #
        # Returns an array of Hash objects with business data that matches the Twirp definition.
        def build_business_list(businesses, admin_role: "")
          businesses.map do |business|
            billing_details = customer_billing_details(business)
            licenses = build_enterprise_server_licenses(business)
            {
              id: business.id,
              name: business.name,
              installations: build_enterprise_installations(business.enterprise_installations),
              slug: business.slug,
              licenses: licenses,
              support_plan: business.calculated_support_plan,
              verified_domains: VerifiableDomain.where(owner: business, verified: true).limit(100).map(&:domain).uniq,
              org_verified_domains: VerifiableDomain.where(owner_id: business.organizations.map(&:id), owner_type: "User", verified: true).limit(1000).map(&:domain).uniq,
              is_advanced_security_purchased: business.advanced_security_purchased?,
              admin_role: admin_role,
              seats_plan_type: business.seats_plan_type,
              seats: business.seats,
              arr: Billing::Pricing.new(account: business).arr.cents,
              country_code: business.billing_contact.country_code,
              billing_type: business.customer&.billing_type,
              business_type: business.business_type,
              is_expired_trial: business.trial_expired? && business.trial_completed_at && business.trial_completed_at < EXPIRED_EA_LIMIT.ago,
              shortcode: business.shortcode,
              billing_term_ends_on: protobuf_timestamp_if_present(business.billing_term_ends_on),
              is_metered_ghe: business.metered_ghe?,
              purchased_products: purchased_products(business, licenses, billing_details),
              billing_target: billing_target(billing_details),
              is_sales_managed_subscription_self_serve_eligible: business.sales_managed_subscription_self_serve_eligible?,
              avatar_url: business.primary_avatar_url,
              salesforce_account_id: business.salesforce_account&.salesforce_id,
            }
          end
        end

        # If the given value is present, format it as a protobuf timestamp. Otherwise, return nil.
        # @param value [DateTime, nil]
        # @return [Google::Protobuf::Timestamp, nil]
        def protobuf_timestamp_if_present(value)
          value.present? ? Google::Protobuf::Timestamp.new(seconds: value.to_time.to_i) : nil
        end
      end
    end
  end
end
