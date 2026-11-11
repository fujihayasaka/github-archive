# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    class CcrDirectOrgBilling
      class << self
        include Copilot::Policy

        include Copilot::Policies::Concerns::Core
        include Copilot::Policies::Concerns::Business::Mutable
        include Copilot::Policies::Concerns::Business::Mailable
        include Copilot::Policies::Concerns::Organization::Mutable
        include Copilot::Policies::Concerns::Organization::Mailable

        include Copilot::Policies::Concerns::Business::Propagatable
        include Copilot::Policies::Concerns::Instrumentable

        sig { override.returns(String) }
        def config_name
          "ccr_direct_org_billing"
        end

        sig { override.returns(String) }
        def display_name
          "Copilot code review direct billing"
        end

        sig { override.returns(String) }
        def documentation_url
          # No docs...yet?
          ""
        end

        sig { override.params(business: Copilot::Business).returns(Copilot::Policies::PolicyDescription) }
        def business_setting_description(business)
          [
            "All members in this enterprise can use Copilot code review on their pull requests in github.com. If configured,",
            PolicyDescriptionChunk.new(text: "Automatic code review", href: Copilot::CODE_REVIEW_CONFIGURING_AUTO_DOCS_URL),
            "will run for all pull requests in this enterprise. Premium requests consumed will be billed as paid usage directly to your enterprise.",
          ]
        end

        sig { override.params(org: Copilot::Organization).returns(Copilot::Policies::PolicyDescription) }
        def organization_setting_description(org)
          [
            "All members in this organization can use Copilot code review on their pull requests in github.com. If configured,",
            PolicyDescriptionChunk.new(text: "Automatic code review", href: Copilot::CODE_REVIEW_CONFIGURING_AUTO_DOCS_URL),
            "will run for all pull requests in this organization. Premium requests consumed will be billed as paid usage directly to your organization.",
          ]
        end

        sig { override.params(copilot_business: Copilot::Business).returns(T::Boolean) }
        def viewable_by_business?(copilot_business)
          super && Copilot::Policies::CodeReview.enabled?(copilot_business)
        end

        sig { override.params(copilot_business: Copilot::Business).returns(T::Boolean) }
        def editable_by_business?(copilot_business)
          super && code_review_overage_enabled?(copilot_business)
        end

        sig { override.params(copilot_org: Copilot::Organization).returns(T::Boolean) }
        def viewable_by_org?(copilot_org)
          # TODO: since you can't edit unless you have a business, should we even show it to orgs without businesses?
          # TODO: currently, we check if CCR is enabled on the frontend, can that move here?
          super
        end

        sig { override.params(copilot_org: Copilot::Organization).returns(T::Boolean) }
        def editable_by_org?(copilot_org)
          return false unless super

          copilot_business = copilot_org.copilot_business

          # we don't need to check for no policy since super will do that
          return false unless copilot_business

          code_review_overage_enabled?(copilot_business)
        end

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def available_for?(entity)
          return false unless entity.feature_flag_enabled?(:copilot_code_review_direct_org_billing, default: false)

          # This is an organization/business-only policy
          # Users don't have their own policy value - they use their organization's setting
          return false if entity.sorbet_class == ::User

          true
        end

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def editable_by?(entity)
          return false unless available_for?(entity)

          case entity.sorbet_class.to_s
          when "Business"
            # Business can always edit if PRU is enabled
            code_review_overage_enabled?(entity)
          when "Organization"
            # Organizations can edit if the business has set "no_policy" AND PRU is enabled
            org = T.cast(entity, Copilot::Organization)
            business = org.business
            return false unless business

            copilot_business = Copilot::Business.new(business)
            business_value = copilot_business.configuration.ccr_direct_org_billing

            # If business has no_policy, org can configure (but only if PRU is enabled at business level)
            return false unless business_value == "no_policy"
            code_review_overage_enabled?(copilot_business)
          else
            false
          end
        end

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def preview?(entity)
          false
        end

        # This policy is only configured at the organization and business level
        # Users don't have individual policy values - they inherit from their organization
        # Returns "unconfigured" to indicate this policy doesn't apply at the user level
        sig { override.params(user: Copilot::User, all_policies: T.nilable(Copilot::Users::Policies::CopilotAllPolicies)).returns(String) }
        def effective_value(user, all_policies = nil)
          "unconfigured"
        end

        sig { override.returns(T::Boolean) }
        def skip_user_instrumentation?
          true
        end

        sig { override.params(copilot_business: Copilot::Business, value: String).void }
        def post_business_update(copilot_business, value)
          # When business sets no_policy, propagate disabled to all orgs
          # This gives orgs a clean slate to configure individually
          if value == "no_policy"
            copilot_business.organizations.each do |org|
              copilot_org = Copilot::Organization.new(org)
              # Only update if not already disabled to avoid unnecessary DB writes/events
              # Don't send user emails - only admin emails will be sent by the batch job
              unless value(copilot_org) == "disabled"
                update_org(copilot_org, "disabled", send_email: false)
              end
            end
          end
        end

        # Override the default email sending behavior to target users WITHOUT seats
        sig { override.params(copilot_org: Copilot::Organization, value: String, previous_value: String).void }
        def send_policy_updated_email(copilot_org, value:, previous_value:)
          return if skip_email?(copilot_org)
          org = copilot_org.organization_object

          # Get IDs of users with seats using a single efficient query
          user_ids_with_seats = Copilot::Seat.for_organization(org).pluck(:assigned_user_id)

          # Send emails to org members who don't have seats
          org.members.where.not(id: user_ids_with_seats).find_each do |user|
            if value == config_values[:disabled] && previous_value == config_values[:enabled]
              send_policy_disabled_email(org, user)
            elsif value == config_values[:enabled]
              send_policy_enabled_email(org, user)
            end
          end
        end

        sig { override.params(org: ::Organization, user: ::User).void }
        def send_policy_enabled_email(org, user)
          CopilotCodeReviewDirectOrgBillingMailer.direct_org_billing_enabled_for_user(org, user).deliver_later
        end

        sig { override.params(org: ::Organization, user: ::User).void }
        def send_policy_disabled_email(org, user)
          CopilotCodeReviewDirectOrgBillingMailer.direct_org_billing_disabled_for_user(org, user).deliver_later
        end

        sig { override.params(org: ::Organization, admin: ::User).void }
        def send_policy_enabled_email_to_admin(org, admin)
          CopilotCodeReviewDirectOrgBillingMailer.direct_org_billing_enabled_for_org_admin(org, admin).deliver_later
        end

        sig { override.params(org: ::Organization, admin: ::User).void }
        def send_policy_no_policy_email_to_admin(org, admin)
          CopilotCodeReviewDirectOrgBillingMailer.direct_org_billing_no_policy_for_org_admin(org, admin).deliver_later
        end

        sig { override.params(org: ::Organization, admin: ::User).void }
        def send_policy_disabled_email_to_admin(org, admin)
          CopilotCodeReviewDirectOrgBillingMailer.direct_org_billing_disabled_for_org_admin(org, admin).deliver_later
        end

        sig { override.params(org: Copilot::Organization).returns(T::Boolean) }
        def skip_email?(org)
          # Check both the policy feature flag and the email feature flag
          return true unless org.feature_flag_enabled?(:copilot_code_review_direct_org_billing, default: false)
          !org.feature_flag_enabled?(:copilot_code_review_emails, default: false)
        end

        sig { override.params(org: Copilot::Organization).returns(T::Boolean) }
        def skip_admin_email?(org)
          # Use the same logic as skip_email? for admin emails
          skip_email?(org)
        end

        sig { override.returns(T::Boolean) }
        def send_user_emails_on_propagation?
          # Don't send user emails when enterprise policy propagates to orgs
          # Only send admin emails to reduce email spam
          false
        end

        private

        sig { params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def code_review_overage_enabled?(entity)
          # Get the business entity - either directly or through organization
          business = case entity.sorbet_class.to_s
          when "Business"
            T.cast(entity, Copilot::Business)
          when "Organization"
            T.cast(entity, Copilot::Organization).business
          else
            return false
          end

          return false unless business&.customer

          customer_id = T.must(business.customer).id
          billing_client = ::Billing::Platform::Api::Client.new

          policy_response = billing_client.get_overage_policy(
            customer_id: customer_id,
            overage_policy_type: "sku",
            name: "code_review_premium_request",
            is_for_business: true
          )

          return false if policy_response.is_a?(::Billing::Platform::Api::Error)

          policy_response[:overagePolicy][:enabled] == true
        rescue => e
          Failbot.report(e)
          false
        end

        sig do override.returns({
            enabled: Symbol,
            disabled: Symbol,
            no_policy: Symbol,
            unconfigured: Symbol,
            unknown: Symbol
          })
        end
        def instrumentation_symbols
          {
            enabled: :CCR_DIRECT_ORG_BILLING_ENABLED,
            disabled: :CCR_DIRECT_ORG_BILLING_DISABLED,
            no_policy: :CCR_DIRECT_ORG_BILLING_NO_POLICY,
            unconfigured: :CCR_DIRECT_ORG_BILLING_UNCONFIGURED,
            unknown: :CCR_DIRECT_ORG_BILLING_UNKNOWN
          }
        end
      end
    end
  end
end
