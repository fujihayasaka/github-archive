# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    class CliDirectOrgBilling
      class << self
        include Copilot::PolicyInterface

        include Copilot::Policies::Concerns::Core
        include Copilot::Policies::Concerns::Business::Mutable
        include Copilot::Policies::Concerns::Organization::Mutable

        include Copilot::Policies::Concerns::Business::Propagatable
        include Copilot::Policies::Concerns::Instrumentable

        sig { override.returns(String) }
        def config_name
          "cli_direct_org_billing"
        end

        sig { override.returns(String) }
        def display_name
          "Copilot CLI direct billing"
        end

        sig { override.returns(String) }
        def documentation_url
          # TODO: add documentation url when appropriate, no docs yet.
          ""
        end

        sig { override.params(business: Copilot::Business).returns(Copilot::Policies::PolicyDescription) }
        def business_setting_description(business)
          [
            "All members in this enterprise can use GitHub Copilot CLI in the terminal. Premium requests consumed will be billed as paid usage directly to your enterprise.",
          ]
        end

        sig { override.params(org: Copilot::Organization).returns(Copilot::Policies::PolicyDescription) }
        def organization_setting_description(org)
          [
            "All members in this organization can use GitHub Copilot CLI in the terminal. Premium requests consumed will be billed as paid usage directly to your organization.",
          ]
        end

        sig { override.params(copilot_business: Copilot::Business).returns(T::Boolean) }
        def viewable_by_business?(copilot_business)
          super && Copilot::Policies::Cli.enabled?(copilot_business)
        end

        sig { override.params(copilot_business: Copilot::Business).returns(T::Boolean) }
        def editable_by_business?(copilot_business)
          super && cli_overage_enabled?(copilot_business) && has_copilot_seats?(copilot_business)
        end

        sig { override.params(copilot_org: Copilot::Organization).returns(T::Boolean) }
        def viewable_by_org?(copilot_org)
          super
        end

        sig { override.params(copilot_org: Copilot::Organization).returns(T::Boolean) }
        def editable_by_org?(copilot_org)
          return false unless super

          copilot_business = copilot_org.copilot_business

          if copilot_business
            return false unless cli_overage_enabled?(copilot_business)
            has_copilot_seats?(copilot_org)
          else
            cli_overage_enabled?(copilot_org) && has_copilot_seats?(copilot_org)
          end
        end

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def available_for?(entity)
          return false unless entity.feature_flag_enabled?(:copilot_cli_direct_org_billing, default: false)
          return false if entity.sorbet_class == ::User

          true
        end

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def editable_by?(entity)
          return false unless available_for?(entity)

          case entity.sorbet_class.to_s
          when "Business"
            cli_overage_enabled?(entity) && has_copilot_seats?(entity)
          when "Organization"
            org = T.cast(entity, Copilot::Organization)
            business = org.business

            if business
              copilot_business = Copilot::Business.new(business)

              return false unless no_policy?(copilot_business)
              return false unless cli_overage_enabled?(copilot_business)
              has_copilot_seats?(org)
            else
              cli_overage_enabled?(org) && has_copilot_seats?(org)
            end
          else
            false
          end
        end

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def preview?(entity)
          true
        end

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
          if value == "no_policy"
            orgs_to_update = copilot_business.copilot_organizations.select do |copilot_org|
              value(copilot_org) != "disabled"
            end
            bulk_update_orgs(orgs_to_update, "disabled", send_email: false)
          end
        end

        private

        sig { params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def has_copilot_seats?(entity)
          Copilot::Organizations::DirectBilling.has_copilot_seats_for_entity?(entity)
        end

        sig { params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def cli_overage_enabled?(entity)
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
            name: "copilot_premium_request",
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
            enabled: :CLI_DIRECT_ORG_BILLING_ENABLED,
            disabled: :CLI_DIRECT_ORG_BILLING_DISABLED,
            no_policy: :CLI_DIRECT_ORG_BILLING_NO_POLICY,
            unconfigured: :CLI_DIRECT_ORG_BILLING_UNCONFIGURED,
            unknown: :CLI_DIRECT_ORG_BILLING_UNKNOWN
          }
        end
      end
    end
  end
end
