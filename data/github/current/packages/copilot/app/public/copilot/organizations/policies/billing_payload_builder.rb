# typed: strict
# frozen_string_literal: true

module Copilot
  module Organizations
    module Policies
      class BillingPayloadBuilder
        include GitHub::Memoizer
        include ::Billing::TokenBasedBilling

        OVERAGE_POLICY_DEFINITIONS = T.let({
          copilot_premium_request: { type: "sku", name: "copilot_premium_request" },
          coding_agent_premium_request: { type: "sku", name: "coding_agent_premium_request" },
          spark: { type: "product", name: "spark" },
          code_review_premium_request: { type: "sku", name: "code_review_premium_request" },
          copilot_ai_unit: { type: "sku", name: "copilot_ai_unit" },
          coding_agent_ai_unit: { type: "sku", name: "coding_agent_ai_unit" },
          spark_ai_unit: { type: "sku", name: "spark_ai_unit" },
        }.freeze, T::Hash[Symbol, T::Hash[Symbol, String]])

        NON_TBB_POLICY_KEYS = T.let([
          :copilot_premium_request,
          :coding_agent_premium_request,
          :spark,
          :code_review_premium_request,
        ].freeze, T::Array[Symbol])

        TBB_POLICY_KEYS = T.let([
          :copilot_ai_unit,
          :coding_agent_ai_unit,
          :spark_ai_unit,
        ].freeze, T::Array[Symbol])

        sig { params(organization: ::Copilot::Organization).void }
        def initialize(organization:)
          @organization = organization
        end

        sig { params(overage_policies: Copilot::Types::BillingOveragesPayload).returns(Copilot::Types::CcrDirectOrgBillingPolicyPayload) }
        def ccr_direct_org_billing_policy_hash(overage_policies)
          policy_class = Copilot::Policies::CcrDirectOrgBilling
          base_hash = opt_in_policy_hash(policy_class)

          # Get PRU (Premium Request Usage) status from the overage policies
          pru_enabled = overage_policies[:code_review_premium_request][:value]

          base_hash.merge(pru_enabled: pru_enabled)
        end

        sig { params(overage_policies: Copilot::Types::BillingOveragesPayload).returns(Copilot::Types::CcaDirectOrgBillingPolicyPayload) }
        def cca_direct_org_billing_policy_hash(overage_policies)
          policy_class = Copilot::Policies::CcaDirectOrgBilling
          base_hash = opt_in_policy_hash(policy_class)

          pru_enabled = overage_policies[:coding_agent_premium_request][:value]

          base_hash.merge(pru_enabled: pru_enabled)
        end

        sig { params(overage_policies: Copilot::Types::BillingOveragesPayload).returns(Copilot::Types::CliDirectOrgBillingPolicyPayload) }
        def cli_direct_org_billing_policy_hash(overage_policies)
          policy_class = Copilot::Policies::CliDirectOrgBilling
          base_hash = opt_in_policy_hash(policy_class)

          pru_enabled = overage_policies[:copilot_premium_request][:value]

          base_hash.merge(pru_enabled: pru_enabled)
        end

        sig { returns(Copilot::Types::BillingOveragesPayload) }
        def get_overage_policies
          delegate_billing = @organization.business.present?
          customer = nil

          if delegate_billing
            customer = @organization.business&.customer
          else
            customer = @organization.customer
          end

          organization_token_based_billing_enabled = T.let(billing_tbb_enabled?(@organization.organization_object), T::Boolean)
          business_org_token_based_billing_enabled = T.let(false, T::Boolean)
          if @organization.business.present?
            business_org_token_based_billing_enabled = billing_tbb_enabled?(T.must(@organization.business))
          end
          token_based_billing_enabled = organization_token_based_billing_enabled || business_org_token_based_billing_enabled

          fetched_policy_keys = if token_based_billing_enabled
            NON_TBB_POLICY_KEYS + TBB_POLICY_KEYS
          else
            NON_TBB_POLICY_KEYS
          end

          responses = {}
          fetched_policy_keys.each do |key|
            details = T.must(OVERAGE_POLICY_DEFINITIONS[key])
            if customer.present?
              responses[key] = billing_platform_client.get_overage_policy(
                customer_id: customer.id,
                overage_policy_type: details[:type],
                name: details[:name],
                is_for_business: true
              )
            end
          end
          has_error = responses.values.any? { |response| response.is_a?(::Billing::Platform::Api::Error) }

          if has_error
            error_response = responses.values.find { |response| response.is_a?(::Billing::Platform::Api::Error) }
            Failbot.report(error_response)
            GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:503", "operation:billing/get_overage_policy"])
          else
            GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:200", "operation:billing/get_overage_policy"])
          end

          result = T.let({
            visible: !has_error,
            value: false,
            token_based_billing: token_based_billing_enabled,
            copilot_premium_request: { value: false, visible: !has_error && !token_based_billing_enabled },
            coding_agent_premium_request: { value: false, visible: !has_error && !token_based_billing_enabled },
            spark: { value: false, visible: !has_error && !token_based_billing_enabled },
            code_review_premium_request: { value: false, visible: !has_error && !token_based_billing_enabled },
            copilot_ai_unit: { value: false, visible: !has_error && token_based_billing_enabled },
            coding_agent_ai_unit: { value: false, visible: !has_error && token_based_billing_enabled },
            spark_ai_unit: { value: false, visible: !has_error && token_based_billing_enabled }
          }, Copilot::Types::BillingOveragesPayload)

          unless has_error
            fetched_policy_keys.each do |policy_key|
              response = responses[policy_key]
              if !response.is_a?(::Billing::Platform::Api::Error) && response.present? && response[:overagePolicy].present? && response[:overagePolicy][:enabled]
                result[policy_key][:value] = true
              end
            end
          end

          # set this value to the copilot_premium_request value for backwards compatibility as github-ui will check for this before both parts are rolled out
          result[:value] = result[:copilot_premium_request][:value]
          result
        end

        private

        sig { params(policy_class: Copilot::Types::OrgMutablePolicy).returns(Copilot::Types::PoliciesIndexPayloadOptInAspect) }
        def opt_in_policy_hash(policy_class)
          {
            manages: policy_class.config_name,
            visible: policy_class.viewable_by_org?(@organization),
            configurable: policy_class.editable_by?(@organization),
            enabled: policy_class.enabled?(@organization)
          }
        end

        sig { returns(::Billing::Platform::Api::Client) }
        memoize def billing_platform_client
          ::Billing::Platform::Api::Client.new
        end
      end
    end
  end
end
