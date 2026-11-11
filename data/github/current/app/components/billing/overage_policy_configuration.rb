# typed: strict
# frozen_string_literal: true

module Billing
  class OveragePolicyConfiguration
    COPILOT_PREMIUM_REQUEST = "copilot_premium_request"
    SPARK = "spark"
    CODING_AGENT_PREMIUM_REQUEST = "coding_agent_premium_request"
    CODING_AGENT_AI_UNIT = "coding_agent_ai_unit"
    SPARK_AI_UNIT = "spark_ai_unit"
    COPILOT_AI_UNIT = "copilot_ai_unit"

    ENTERPRISE = "enterprise"
    ORGANIZATION = "organization"
    ENTERPRISE_OWNED_ORG = "enterprise_owned_org"

    SINGLE_SELECT = "single"
    MULTI_SELECT = "multi"

    PRODUCT = "product"
    SKU = "sku"

    class << self
      sig { params(policy_name: String, tbb_enabled: T::Boolean).returns(T::Hash[String, T.untyped]) }
      def metadata_for(policy_name, tbb_enabled: false)
        case policy_name
        when COPILOT_PREMIUM_REQUEST
          copilot_premium_request_metadata(tbb_enabled:)
        else
          {}
        end
      end

      private

      sig { params(tbb_enabled: T::Boolean).returns(T::Hash[String, T.untyped]) }
      def copilot_premium_request_metadata(tbb_enabled:)
        {
          SINGLE_SELECT => single_select_config(tbb_enabled:),
          MULTI_SELECT => multi_select_config(tbb_enabled:)
        }
      end

      sig { params(tbb_enabled: T::Boolean).returns(T::Hash[String, T.untyped]) }
      def single_select_config(tbb_enabled:)
        {
          contexts: {
            ENTERPRISE => enterprise_single_context(tbb_enabled:),
            ORGANIZATION => organization_single_context(tbb_enabled:),
            ENTERPRISE_OWNED_ORG => enterprise_owned_org_context(tbb_enabled:)
          }
        }
      end

      sig { params(tbb_enabled: T::Boolean).returns(T::Hash[String, T.untyped]) }
      def multi_select_config(tbb_enabled:)
        {
          contexts: {
            ENTERPRISE => enterprise_multi_context(tbb_enabled:),
            ORGANIZATION => organization_multi_context(tbb_enabled:),
            ENTERPRISE_OWNED_ORG => enterprise_owned_org_context(tbb_enabled:)
          }
        }
      end

      # Context builders
      sig { params(tbb_enabled: T::Boolean).returns(T::Hash[Symbol, T.untyped]) }
      def enterprise_single_context(tbb_enabled: false)
        {
          title: tbb_enabled ? "AI credit paid usage" : "Premium request paid usage",
          description: if tbb_enabled
                         "When enabled, all organizations in your enterprise will be charged for AI credits that exceed their included usage. "
                       else
                         "When enabled, all organizations in your enterprise will be charged for premium requests that exceed their included usage. "
                       end,
          options: [
            single_enabled_option(tbb_enabled ? "Your organizations will be charged for AI credits that exceed your included usage. Organizations can set a budget to control their maximum spend." : "Your organizations will be charged for premium requests that exceed your included usage. Organizations can set a budget to control their maximum spend."),
            multi_select_option(tbb_enabled ? "Organizations will only be billed for AI credit paid usage from the selected products. This cannot be changed at the organization level." : "Organizations will only be billed for premium request paid usage from the selected products. This cannot be changed at the organization level."),
            single_disabled_option(tbb_enabled ? "Your organizations will not be charged for AI credit overages. This setting is controlled at the enterprise level." : "Your organizations will not be charged for premium request overages. This setting is controlled at the enterprise level.")
          ]
        }
      end

      sig { params(tbb_enabled: T::Boolean).returns(T::Hash[Symbol, T.untyped]) }
      def organization_single_context(tbb_enabled: false)
        {
          title: tbb_enabled ? "AI credit paid usage" : "Premium request paid usage",
          description: if tbb_enabled
                         "When enabled, your organization will be charged for AI credits that exceed your included usage. "
                       else
                         "When enabled, your organization will be charged for premium requests that exceed your included usage. "
                       end,
          options: [
            single_enabled_option(tbb_enabled ? "Your organization will be charged for AI credits that exceed your included usage." : "Your organization will be charged for premium requests that exceed your included usage."),
            multi_select_option(tbb_enabled ? "Your organization will only be billed for AI credit paid usage from the selected products." : "Your organization will only be billed for premium request paid usage from the selected products."),
            single_disabled_option(tbb_enabled ? "Your organization will not be charged for AI credit overages." : "Your organization will not be charged for premium request overages.")
          ]
        }
      end

      sig { params(tbb_enabled: T::Boolean).returns(T::Hash[Symbol, T.untyped]) }
      def enterprise_multi_context(tbb_enabled: false)
        premium_request_options = [
          multi_product_option(COPILOT_PREMIUM_REQUEST, "Opt in to Copilot premium request paid usage", "Enables billing for Copilot premium requests"),
          multi_product_option(SPARK, "Opt in to Spark premium request paid usage", "Enables billing for Spark premium requests"),
          multi_product_option(CODING_AGENT_PREMIUM_REQUEST, "Opt in to Cloud Agent premium request paid usage", "Enables overages for Copilot cloud agent premium requests")
        ]

        ai_credit_options = [
          multi_product_option(CODING_AGENT_AI_UNIT, "Opt in to Cloud Agent AI credit paid usage", "Enables billing for Cloud Agent AI credits"),
          multi_product_option(SPARK_AI_UNIT, "Opt in to Spark AI credit paid usage", "Enables billing for Spark AI credits"),
          multi_product_option(COPILOT_AI_UNIT, "Opt in to Copilot AI credit paid usage", "Enables billing for Copilot AI credits")
        ]

        {
          title: tbb_enabled ? "AI credit paid usage" : "Premium request paid usage",
          description: if tbb_enabled
                         "If enabled, all organizations in your enterprise will be billed for AI credit paid usage "
                       else
                         "If enabled, all organizations in your enterprise will be billed for premium request paid usage "
                       end,
          options: tbb_enabled ? ai_credit_options : premium_request_options
        }
      end

      sig { params(tbb_enabled: T::Boolean).returns(T::Hash[Symbol, T.untyped]) }
      def organization_multi_context(tbb_enabled: false)
        premium_request_options = [
          multi_product_option(COPILOT_PREMIUM_REQUEST, "Opt in to Copilot premium request paid usage", "Enables billing for Copilot premium requests"),
          multi_product_option(SPARK, "Opt in to Spark premium request paid usage", "Enables billing for Spark premium requests"),
          multi_product_option(CODING_AGENT_PREMIUM_REQUEST, "Opt in to Cloud Agent premium request paid usage", "Enables overages for Copilot cloud agent premium requests")
        ]

        ai_credit_options = [
          multi_product_option(CODING_AGENT_AI_UNIT, "Opt in to Cloud Agent AI credit paid usage", "Enables billing for Cloud Agent AI credits"),
          multi_product_option(SPARK_AI_UNIT, "Opt in to Spark AI credit paid usage", "Enables billing for Spark AI credits"),
          multi_product_option(COPILOT_AI_UNIT, "Opt in to Copilot AI credit paid usage", "Enables billing for Copilot AI credits")
        ]

        {
          title: tbb_enabled ? "AI credit paid usage" : "Premium request paid usage",
          description: if tbb_enabled
                         "If enabled, your organization will be billed for AI credit paid usage. "
                       else
                         "If enabled, your organization will be billed for premium request paid usage. "
                       end,
          options: tbb_enabled ? ai_credit_options : premium_request_options
        }
      end

      sig { params(tbb_enabled: T::Boolean).returns(T::Hash[Symbol, T.untyped]) }
      def enterprise_owned_org_context(tbb_enabled: false)
        {
          title: tbb_enabled ? "AI credit paid usage" : "Premium request paid usage",
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
