# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Copilot
  module Organizations
    module InstrumentationDetails
      extend T::Helpers
      extend T::Sig
      include Copilot::Organizations::Signatures

      abstract!

      sig { override.returns(T.nilable(String)) }
      def copilot_billing_type
        # This is a very hacky method but we gotta do it.
        # The billing type can come from the organization, from a customer associated with the organization, from the business (if enterprise linked) or from the business' customer (if enterprise linked)
        org_billing_type              = organization_object.billing_type # this is the organization's billing type
        org_customer_billing_type     = organization_object.customer&.billing_type # this is the organization's customer's billing type
        org_biz_billing_type          = organization_object.business&.billing_type # this is the organization's business' billing type
        org_biz_customer_billing_type = organization_object.business&.customer&.billing_type # this is the organization's business' customer's billing type

        billing_types = [
          org_biz_customer_billing_type, # look at this first
          org_biz_billing_type, # then look at this
          org_customer_billing_type, # then look at this
          org_billing_type, # finally this
        ].compact.uniq

        tags = [
          "org_billing_type:#{org_billing_type}",
          "org_customer_billing_type:#{org_customer_billing_type}",
          "org_biz_billing_type:#{org_biz_billing_type}",
          "org_biz_customer_billing_type:#{org_biz_customer_billing_type}"
        ]

        # let's see if we have more than one billing types
        if billing_types.length > 1
          # we are just going to log this
          billing_types.each_with_index do |billing_type, index|
            tags << "billing_types_#{index}:#{billing_type}"
          end

          GitHub.logger.info(
            "copilot_billing_type: More than one billing type found",
            "gh.org.id" => organization_object.id,
            "gh.org.billing_type" => org_billing_type,
            "gh.org.customer.billing_type" => org_customer_billing_type,
            "gh.org.business.billing_type" => org_biz_billing_type,
            "gh.org.business.customer.billing_type" => org_biz_customer_billing_type,
          )
        end

        billing_type = billing_types.first
        GitHub.dogstats.increment(
          "copilot.billing_type.org_billing_type",
          tags: tags
        )
        billing_type
      end

      sig { override.returns(Symbol) }
      def copilot_snippy_setting
        return :SNIPPY_ENABLED if block_public_code_suggestions?
        return :SNIPPY_DISABLED if allow_public_code_suggestions?
        return :SNIPPY_UNCONFIGURED unless public_code_suggestions_configured?

        :SNIPPY_UNKNOWN
      end

      # NEVER HAS :EDITOR_CHAT_NO_POLICY
      sig { override.returns(Symbol) }
      def copilot_editor_chat_setting
        return :EDITOR_CHAT_ENABLED if chat_enabled?
        return :EDITOR_CHAT_DISABLED if chat_disabled?
        return :EDITOR_CHAT_UNCONFIGURED unless chat_enabled_configured?

        :EDITOR_CHAT_UNKNOWN
      end

      sig { override.returns(Symbol) }
      def copilot_mobile_chat_setting
        return :MOBILE_CHAT_ENABLED if mobile_chat_enabled?
        return :MOBILE_CHAT_DISABLED if mobile_chat_disabled?

        :MOBILE_CHAT_UNKNOWN
      end

      sig { override.returns(Symbol) }
      def copilot_enabled_setting
        return :COPILOT_ENABLED if copilot_configuration_setting_enabled?
        return :COPILOT_DISABLED if copilot_disabled?

        :COPILOT_UNKNOWN
      end

      sig { override.returns(Symbol) }
      def copilot_usage_telemetry_api_setting
        return :USAGE_TELEMETRY_API_ENABLED if telemetry_aggregation_enabled?
        return :USAGE_TELEMETRY_API_DISABLED if !telemetry_aggregation_enabled?

        :USAGE_TELEMETRY_API_UNKNOWN
      end

      sig { override.returns(Symbol) }
      def copilot_github_chat_setting
        return :GITHUB_CHAT_UNCONFIGURED unless dotcom_chat_configured?
        return :GITHUB_CHAT_ENABLED if dotcom_chat_enabled?
        return :GITHUB_CHAT_DISABLED if dotcom_chat_disabled?
        return :GITHUB_CHAT_NO_POLICY if dotcom_chat_no_policy?

        :GITHUB_CHAT_UNKNOWN
      end

      sig { override.returns(Symbol) }
      def copilot_github_chat_bing_access_setting
        return :GITHUB_CHAT_BING_ACCESS_ENABLED if bing_github_chat_enabled?
        return :GITHUB_CHAT_BING_ACCESS_DISABLED if bing_github_chat_disabled?

        :GITHUB_CHAT_BING_ACCESS_UNKNOWN
      end

      sig { override.returns(Symbol) }
      def copilot_user_feedback_opt_in_setting
        return :COPILOT_USER_FEEDBACK_OPT_IN_ENABLED if user_feedback_opt_in_enabled?
        return :COPILOT_USER_FEEDBACK_OPT_IN_DISABLED if user_feedback_opt_in_disabled?

        :COPILOT_USER_FEEDBACK_OPT_IN_UNKNOWN
      end

      sig { override.returns(Symbol) }
      def copilot_custom_models_setting
        return :CUSTOM_MODELS_UNCONFIGURED unless custom_models_configured?
        return :CUSTOM_MODELS_ENABLED if custom_models_enabled?
        return :CUSTOM_MODELS_DISABLED if custom_models_disabled?
        return :CUSTOM_MODELS_NO_POLICY if custom_models_no_policy?

        :CUSTOM_MODELS_UNKNOWN
      end

      sig { override.returns(Symbol) }
      def copilot_extensions_policy_setting
        return :COPILOT_EXTENSIONS_UNCONFIGURED unless copilot_extensions_configured?
        return :COPILOT_EXTENSIONS_ENABLED if copilot_extensions_enabled?
        return :COPILOT_EXTENSIONS_DISABLED if copilot_extensions_disabled?
        return :COPILOT_EXTENSIONS_NO_POLICY if copilot_extensions_no_policy?

        :COPILOT_EXTENSIONS_UNKNOWN
      end

      sig { override.returns(Symbol) }
      def copilot_private_docs_setting
        return :PRIVATE_DOCS_UNCONFIGURED unless private_docs_configured?
        return :PRIVATE_DOCS_ENABLED if private_docs_enabled?
        return :PRIVATE_DOCS_DISABLED if private_docs_disabled?
        return :PRIVATE_DOCS_NO_POLICY if private_docs_no_policy?

        :PRIVATE_DOCS_UNKNOWN
      end

      sig { override.returns(Symbol) }
      def copilot_pr_summarizations_setting
        return :PR_SUMMARIZATIONS_UNCONFIGURED unless pr_summarizations_configured?
        return :PR_SUMMARIZATIONS_ENABLED if pr_summarizations_enabled?
        return :PR_SUMMARIZATIONS_DISABLED if pr_summarizations_disabled?
        return :PR_SUMMARIZATIONS_NO_POLICY if pr_summarizations_no_policy?

        :PR_SUMMARIZATIONS_UNKNOWN
      end

      sig { override.returns(Symbol) }
      def copilot_cli_setting
        return :CLI_UNCONFIGURED unless cli_configured?
        return :CLI_ENABLED if cli_enabled?
        return :CLI_DISABLED if cli_disabled?

        :CLI_UNKNOWN
      end

      sig { returns(Symbol) }
      def copilot_private_telemetry_setting
        return :PRIVATE_TELEMETRY_UNCONFIGURED unless private_telemetry_configured?
        return :PRIVATE_TELEMETRY_ENABLED if private_telemetry_enabled?
        return :PRIVATE_TELEMETRY_DISABLED if private_telemetry_disabled?

        :PRIVATE_TELEMETRY_UNKNOWN
      end

      sig { override.returns(Symbol) }
      def copilot_beta_features_opt_in_setting
        return :COPILOT_BETA_FEATURES_OPT_IN_ENABLED if beta_features_github_chat_enabled?
        return :COPILOT_BETA_FEATURES_OPT_IN_DISABLED if beta_features_github_chat_disabled?

        :COPILOT_BETA_FEATURES_OPT_IN_UNKNOWN
      end

      sig { override.returns(T::Hash[Symbol, Symbol]) }
      def copilot_organization_settings
        {
          cli_setting: copilot_cli_setting,
          copilot_beta_features_opt_in_setting: copilot_beta_features_opt_in_setting,
          copilot_enabled_setting: copilot_enabled_setting,
          copilot_extensions_setting: copilot_extensions_policy_setting,
          copilot_user_feedback_opt_in_setting: copilot_user_feedback_opt_in_setting,
          custom_models_setting: copilot_custom_models_setting,
          editor_chat_setting: copilot_editor_chat_setting,
          github_chat_bing_access_setting: copilot_github_chat_bing_access_setting,
          github_chat_setting: copilot_github_chat_setting,
          mobile_chat_setting: copilot_mobile_chat_setting,
          pr_summarizations_setting: copilot_pr_summarizations_setting,
          private_docs_setting: copilot_private_docs_setting,
          private_telemetry_setting: copilot_private_telemetry_setting,
          snippy_setting: copilot_snippy_setting,
          usage_telemetry_api_setting: copilot_usage_telemetry_api_setting,
        }
      end
    end
  end
end
