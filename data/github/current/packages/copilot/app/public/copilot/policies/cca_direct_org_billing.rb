# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    class CcaDirectOrgBilling
      class << self
        include Copilot::PolicyInterface

        include Copilot::Policies::Concerns::Core
        include Copilot::Policies::Concerns::Business::Mutable
        include Copilot::Policies::Concerns::Organization::Mutable

        include Copilot::Policies::Concerns::Business::Propagatable
        include Copilot::Policies::Concerns::Instrumentable
        include Copilot::Policies::Concerns::Twirpable

        sig { override.returns(String) }
        def config_name
          "cca_direct_org_billing"
        end

        sig { override.returns(String) }
        def display_name
          "Copilot cloud agent direct billing"
        end

        sig { override.returns(String) }
        def documentation_url
          # No docs so far.
          ""
        end

        sig { override.params(business: Copilot::Business).returns(Copilot::Policies::PolicyDescription) }
        def business_setting_description(business)
          # TODO: this is placeholder text
          [
            "All members in this enterprise can use Copilot cloud agent in repositories where it is enabled. Premium requests consumed will be billed as paid usage directly to your enterprise.",
          ]
        end

        sig { override.params(org: Copilot::Organization).returns(Copilot::Policies::PolicyDescription) }
        def organization_setting_description(org)
          # TODO: this is placeholder text
          [
            "All members in this organization can use Copilot cloud agent in repositories where it is enabled. Premium requests consumed will be billed as paid usage directly to your organization.",
          ]
        end

        sig { override.params(copilot_business: Copilot::Business).returns(T::Boolean) }
        def viewable_by_business?(copilot_business)
          super && Copilot::Policies::CodingAgent.enabled?(copilot_business)
        end

        sig { override.params(copilot_business: Copilot::Business).returns(T::Boolean) }
        def editable_by_business?(copilot_business)
          super && coding_agent_overage_enabled?(copilot_business) && has_copilot_seats?(copilot_business)
        end

        sig { override.params(copilot_org: Copilot::Organization).returns(T::Boolean) }
        def viewable_by_org?(copilot_org)
          # TODO: since most of the checks will happen in react, this is just for initial load of the orgs policy page
          super
        end

        sig { override.params(copilot_org: Copilot::Organization).returns(T::Boolean) }
        def editable_by_org?(copilot_org)
          return false unless super

          copilot_business = copilot_org.copilot_business

          return false unless copilot_business
          return false unless coding_agent_overage_enabled?(copilot_business)

          has_copilot_seats?(copilot_org)
        end

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def available_for?(entity)
          return false unless entity.feature_flag_enabled?(:copilot_coding_agent_direct_org_billing, default: false)

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
            coding_agent_overage_enabled?(entity) && has_copilot_seats?(entity)
          when "Organization"
            org = T.cast(entity, Copilot::Organization)
            business = org.business

            if business
              copilot_business = Copilot::Business.new(business)
              business_value = copilot_business.configuration.cca_direct_org_billing

              return false unless business_value == "no_policy"
              return false unless coding_agent_overage_enabled?(copilot_business)
              has_copilot_seats?(org)
            else
              coding_agent_overage_enabled?(org) && has_copilot_seats?(org)
            end
          else
            false
          end
        end

        sig { override.params(copilot_business: Copilot::Business, value: String).void }
        def update_business(copilot_business, value)
          # When enterprise management is active, prevent setting no_policy
          # because we don't want to allow org-level changes to CcaDirectOrgBilling when the enterprise has decided to centrally manage the policy
          if value == "no_policy" && copilot_business.coding_agent_enterprise_management_enabled?
            return
          end

          super
        end

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def preview?(entity)
          true
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
            orgs_to_update = copilot_business.copilot_organizations.select do |copilot_org|
              value(copilot_org) != "disabled"
            end
            bulk_update_orgs(orgs_to_update, "disabled", send_email: false)
          end
        end

        sig { params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def coding_agent_overage_enabled?(entity)
          # Get the business entity - either directly or through organization
          copilot_entity = case entity.sorbet_class.to_s
          when "Business"
            T.cast(entity, Copilot::Business)
          when "Organization"
            org = T.cast(entity, Copilot::Organization)
            if org.business
              Copilot::Business.new(T.must(org.business))
            else
              org
            end
          else
            return false
          end

          return false unless copilot_entity.customer

          customer_id = T.must(copilot_entity.customer).id
          billing_client = ::Billing::Platform::Api::Client.new

          policy_response = billing_client.get_overage_policy(
            customer_id: customer_id,
            overage_policy_type: "sku",
            name: "coding_agent_premium_request",
            is_for_business: true
          )

          return false if policy_response.is_a?(::Billing::Platform::Api::Error)

          policy_response[:overagePolicy][:enabled] == true
        rescue => e
          Failbot.report(e)
          false
        end

        sig { params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def has_copilot_seats?(entity)
          Copilot::Organizations::DirectBilling.has_copilot_seats_for_entity?(entity)
        end

        private

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
            enabled: :CCA_DIRECT_ORG_BILLING_ENABLED,
            disabled: :CCA_DIRECT_ORG_BILLING_DISABLED,
            no_policy: :CCA_DIRECT_ORG_BILLING_NO_POLICY,
            unconfigured: :CCA_DIRECT_ORG_BILLING_UNCONFIGURED,
            unknown: :CCA_DIRECT_ORG_BILLING_UNKNOWN
          }
        end

        sig do override.returns({
            enabled: Integer,
            disabled: Integer,
            no_policy: Integer,
            unconfigured: Integer,
            invalid: Integer
          })
        end
        def twirp_values
          {
            enabled: MonolithTwirp::Copilot::Users::V1::CCADirectOrgBilling::CCA_DIRECT_ORG_BILLING_ENABLED,
            disabled: MonolithTwirp::Copilot::Users::V1::CCADirectOrgBilling::CCA_DIRECT_ORG_BILLING_DISABLED,
            no_policy: MonolithTwirp::Copilot::Users::V1::CCADirectOrgBilling::CCA_DIRECT_ORG_BILLING_DISABLED,
            unconfigured: MonolithTwirp::Copilot::Users::V1::CCADirectOrgBilling::CCA_DIRECT_ORG_BILLING_UNCONFIGURED,
            invalid: MonolithTwirp::Copilot::Users::V1::CCADirectOrgBilling::CCA_DIRECT_ORG_BILLING_INVALID
          }
        end
      end
    end
  end
end
