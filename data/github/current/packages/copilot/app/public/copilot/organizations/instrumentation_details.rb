# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Copilot
  module Organizations
    module InstrumentationDetails
      extend T::Helpers
      include Copilot::Organizations::Signatures
      include Copilot::Instrumentation::ModelDetails

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
      def copilot_enabled_setting
        return :COPILOT_ENABLED if copilot_configuration_setting_enabled?
        return :COPILOT_DISABLED if copilot_disabled?

        :COPILOT_UNKNOWN
      end

      sig { override.returns(Symbol) }
      def copilot_overages_setting
        return :OVERAGES_UNCONFIGURED unless overages_configured?
        return :OVERAGES_ENABLED if overages_enabled?
        return :OVERAGES_DISABLED if overages_disabled?

        :OVERAGES_UNKNOWN
      end

      sig { returns(Symbol) }
      def copilot_mcp_registry_access
        return :MCP_REGISTRY_ACCESS_ALLOW_ALL if mcp_registry_access_is?("allow_all")
        return :MCP_REGISTRY_ACCESS_REGISTRY_ONLY if mcp_registry_access_is?("registry_only")

        :MCP_REGISTRY_ACCESS_UNKNOWN
      end

      sig { returns(T::Hash[Symbol, T.any(Symbol, String)]) }
      def copilot_mcp_registry_setting
        {
          mcp_registry_url: mcp_registry_url,
          mcp_registry_access: copilot_mcp_registry_access
        }
      end

      sig { override.returns(T::Hash[Symbol, Symbol]) }
      def copilot_organization_settings
        # get the settings hash and merge in some special cases for policies
        # that don't use the new system
        Copilot::Policies.instrumentation_hash(T.bind(self, Copilot::Organization)).merge({
          copilot_enabled_setting: copilot_enabled_setting,
          overages_setting: copilot_overages_setting,
          mcp_registry_setting: copilot_mcp_registry_setting
        })
      end
      alias_method :copilot_settings, :copilot_organization_settings

      sig { params(actor: ::User, old_settings: T::Hash[Symbol, Symbol], new_settings: T::Hash[Symbol, Symbol]).void }
      def instrument_settings_changed(actor, old_settings, new_settings)
        Copilot::Instrumenter.instrument_organization_settings_changed(
          organization_object,
          actor,
          old_settings:,
          new_settings:,
        )
      end
    end
  end
end
