# typed: strict
# frozen_string_literal: true

module Billing
  class OveragePolicyConfiguration
    COPILOT_PREMIUM_REQUEST = "copilot_premium_request"
    SPARK = "spark"
    CODING_AGENT_PREMIUM_REQUEST = "coding_agent_premium_request"

    ENTERPRISE = "enterprise"
    ORGANIZATION = "organization"
    ENTERPRISE_OWNED_ORG = "enterprise_owned_org"

    SINGLE_SELECT = "single"
    MULTI_SELECT = "multi"

    PRODUCT = "product"
    SKU = "sku"

    class << self
      sig { params(policy_name: String).returns(T::Hash[String, T.untyped]) }
      def metadata_for(policy_name)
        case policy_name
        when COPILOT_PREMIUM_REQUEST
          copilot_premium_request_metadata
        else
          {}
        end
      end

      private

      sig { returns(T::Hash[String, T.untyped]) }
      def copilot_premium_request_metadata
        {
          SINGLE_SELECT => single_select_config,
          MULTI_SELECT => multi_select_config
        }
      end

      sig { returns(T::Hash[String, T.untyped]) }
      def single_select_config
        {
          contexts: {
            ENTERPRISE => enterprise_single_context,
            ORGANIZATION => organization_single_context,
            ENTERPRISE_OWNED_ORG => enterprise_owned_org_context
          }
        }
      end

      sig { returns(T::Hash[String, T.untyped]) }
      def multi_select_config
        {
          contexts: {
            ENTERPRISE => enterprise_multi_context,
            ORGANIZATION => organization_multi_context,
            ENTERPRISE_OWNED_ORG => enterprise_owned_org_context
          }
        }
      end

      # Context builders
      sig { returns(T::Hash[Symbol, T.untyped]) }
      def enterprise_single_context
        {
          title: "Premium request paid usage",
          description: "When enabled, all organizations in your enterprise will be charged for premium requests that exceed their included usage. ",
          options: [
            single_enabled_option("Your organizations will be charged for premium requests that exceed your included usage. Organizations can set a budget to control their maximum spend."),
            multi_select_option("Organizations will only be billed for premium request paid usage from the selected products. This cannot be changed at the organization level."),
            single_disabled_option("Your organizations will not be charged for premium request overages. This setting is controlled at the enterprise level.")
          ]
        }
      end

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def organization_single_context
        {
          title: "Premium request paid usage",
          description: "When enabled, your organization will be charged for premium requests that exceed your included usage. ",
          options: [
            single_enabled_option("Your organization will be charged for premium requests that exceed your included usage."),
            multi_select_option("Your organization will only be billed for premium request paid usage from the selected products."),
            single_disabled_option("Your organization will not be charged for premium request overages.")
          ]
        }
      end

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def enterprise_multi_context
        {
          title: "Premium request paid usage",
          description: "If enabled, all organizations in your enterprise will be billed for premium request paid usage ",
          options: [
            multi_product_option(COPILOT_PREMIUM_REQUEST, "Opt in to Copilot premium request paid usage", "Enables billing for Copilot premium requests"),
            multi_product_option(SPARK, "Opt in to Spark premium request paid usage", "Enables billing for Spark premium requests"),
            multi_product_option(CODING_AGENT_PREMIUM_REQUEST, "Opt in to Coding Agent premium request paid usage", "Enables overages for Copilot coding agent premium requests")
          ]
        }
      end

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def organization_multi_context
        {
          title: "Premium request paid usage",
          description: "If enabled, your organization will be billed for premium request paid usage. ",
          options: [
            multi_product_option(COPILOT_PREMIUM_REQUEST, "Opt in to Copilot premium request paid usage", "Enables billing for Copilot premium requests"),
            multi_product_option(SPARK, "Opt in to Spark premium request paid usage", "Enables billing for Spark premium requests"),
            multi_product_option(CODING_AGENT_PREMIUM_REQUEST, "Opt in to Coding Agent premium request paid usage", "Enables overages for Copilot coding agent premium requests")
          ]
        }
      end

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def enterprise_owned_org_context
        {
          title: "Premium request paid usage",
          description: "This setting is controlled at the enterprise level.",
          options: []
        }
      end

      # Option builders
      sig { params(description: String).returns(T::Hash[Symbol, T.untyped]) }
      def single_enabled_option(description)
        {
          label: "Enabled",
          description: description,
          value: "true",
          is_multi_select: false
        }
      end

      sig { params(description: String).returns(T::Hash[Symbol, T.untyped]) }
      def multi_select_option(description)
        {
          label: "Enabled for selected products",
          description: description,
          value: MULTI_SELECT,
          is_multi_select: true
        }
      end

      sig { params(description: String).returns(T::Hash[Symbol, T.untyped]) }
      def single_disabled_option(description)
        {
          label: "Disabled",
          description: description,
          value: "false",
          is_multi_select: false
        }
      end

      sig { params(value: String, label: String, description: String).returns(T::Hash[Symbol, T.untyped]) }
      def multi_product_option(value, label, description)
        {
          label: label,
          description: description,
          value: value,
          is_multi_select: false
        }
      end
    end
  end
end
