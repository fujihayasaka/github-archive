# typed: strict
# frozen_string_literal: true

module Billing
  class OveragePolicyComponent < ApplicationComponent
    include Billing::TokenBasedBilling

    sig do params(
      entity: T.any(User, ::Business),
      overage_policy_type: String,
      name: String,
      ).void
    end
    def initialize(
        entity:,
        overage_policy_type:,
        name:
      )
      @entity = entity
      @overage_policy_type = overage_policy_type
      @name = name

      @policy = T.let(nil, T.nilable(PolicyType))
      @disabled = T.let(false, T::Boolean)
      @policies_available = T.let([], T::Array[String])
      @is_multi_select_enabled = T.let(false, T::Boolean)
      @policies_enabled = T.let([], T::Array[String])
    end

    OptionType = T.type_alias do
      {
        label: String,
        description: String,
        value: String,
        checked?: T::Boolean,
        is_multi_select: T::Boolean,
        is_available: T::Boolean,
      }
    end

    ControlOptionType = T.type_alias do
      {
        label: String,
        description: String,
        value: String,
        checked?: T::Boolean,
        is_multi_select: T::Boolean,
        is_available: T::Boolean,
      }
    end

    PolicyType = T.type_alias do
      {
        title: String,
        description: String,
        options: T::Array[OptionType],
        control_options: T::Array[ControlOptionType]
      }
    end

    PolicyMetadata = T.type_alias do
      {
        contexts: T::Hash[String, PolicyType], # e.g. "enterprise", "organization", "enterprise_owned_org"
      }
    end

    PolicyTypeMap = T.type_alias { T::Hash[String, PolicyMetadata] } # "single" or "multi"
    PolicyMetadataMap = T.type_alias { T::Hash[String, PolicyTypeMap] } # policy names to types of single or multi

    sig { returns(T::Boolean) }
    def has_permission_to_view_policy?
      if @entity.is_a?(::Business) || @entity.is_a?(Organization)
        @entity.adminable_by?(current_user) || T.unsafe(@entity).billing_manager?(current_user)
      else
        @entity.adminable_by?(current_user)
      end
    end

    sig { returns(T.nilable(PolicyType)) }
    memoize def policy
      @policy || configure_overage_policy
    end

    sig { returns(T::Boolean) }
    def render?
      return false unless GitHub.billing_enabled?
      return false unless logged_in?
      return false unless has_permission_to_view_policy?
      return false unless policy.present?

      true
    end

    sig { returns(T::Boolean) }
    def business?
      @entity.is_a?(::Business)
    end

    sig { returns(T::Boolean) }
    def organization?
      @entity.is_a?(Organization)
    end

    sig { returns(T::Boolean) }
    def enterprise_owned_organization?
      organization? && @entity.delegate_billing_to_business?
    end

    sig { params(customer_id: Integer, overage_policy_type: String, name: String, is_for_business: T::Boolean).returns(T.nilable(T::Boolean)) }
    def get_overage_policy(customer_id:, overage_policy_type:, name:, is_for_business:)
      policy_response = billing_platform_client.get_overage_policy(customer_id: customer_id, overage_policy_type: overage_policy_type, name: name, is_for_business: is_for_business)

      # Render nothing if billing platform response isn't working
      if policy_response.is_a?(Billing::Platform::Api::Error)
        Failbot.report(policy_response)
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:503", "operation:billing/get_overage_policy"])
      else
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:200", "operation:billing/get_overage_policy"])
        # See if overages is set on params, if so, use that to override the policy response
        # This is useful for the update action where we want to reflect the change immediately
        # without waiting for the billing platform to update
        enabled_str = policy_response[:overagePolicy][:enabled].nil? ? "false" : policy_response[:overagePolicy][:enabled].to_s

        if params["overages-all"].present?
          return params["overages-all"] == "true"
        elsif params["overages-#{name}"].present?
          return params["overages-#{name}"] == "true"
        else
          return enabled_str == "true"
        end
      end
      nil
    end

    sig { returns(T.nilable(PolicyType)) }
    def configure_overage_policy
      if @overage_policy_type == Billing::OveragePolicyConfiguration::SKU && @name == Billing::OveragePolicyConfiguration::COPILOT_PREMIUM_REQUEST
        customer_id = @entity.customer&.id
        tbb_enabled = tbb_enabled_for_policy_entity?

        # Figure out current entity context
        context = Billing::OveragePolicyConfiguration::ENTERPRISE
        if enterprise_owned_organization?
          @disabled = true
          context = Billing::OveragePolicyConfiguration::ENTERPRISE_OWNED_ORG
          org_entity = T.cast(@entity, Organization)
          customer_id = org_entity.business&.customer_id
        elsif organization?
          context = Billing::OveragePolicyConfiguration::ORGANIZATION
        end

        # Determine which policies are currently available to this entity
        if tbb_enabled
          @policies_available.push(Billing::OveragePolicyConfiguration::CODING_AGENT_AI_UNIT)
          @policies_available.push(Billing::OveragePolicyConfiguration::SPARK_AI_UNIT)
          @policies_available.push(Billing::OveragePolicyConfiguration::COPILOT_AI_UNIT)
        else
          @policies_available.push(Billing::OveragePolicyConfiguration::COPILOT_PREMIUM_REQUEST)
          @policies_available.push(Billing::OveragePolicyConfiguration::SPARK)
          @policies_available.push(Billing::OveragePolicyConfiguration::CODING_AGENT_PREMIUM_REQUEST)
        end

        # Determine which of the available policies are currently enabled, if any
        if customer_id
          @policies_available.each do |name|
            type = name == Billing::OveragePolicyConfiguration::SPARK ? Billing::OveragePolicyConfiguration::PRODUCT : Billing::OveragePolicyConfiguration::SKU  # spark is a product, the rest are skus

            enabled = get_overage_policy(customer_id: customer_id, overage_policy_type: type, name: name, is_for_business: true)

            if enabled.nil?
              # Billing platform error, don't render this component
              return nil
            else
              if enabled
                @policies_enabled.push(name)
              end
            end
          end
        end

        # Determine if we start with multi_select enabled
        # iterate through @policies_enabled map to figure out if any values are different.
        select_context = "single"
        if should_enable_multi_select?
          select_context = "multi"
          @is_multi_select_enabled = true
        end

        # Assemble policy
        metadata = policy_metadata(tbb_enabled: tbb_enabled)
        single_options = metadata["single"][:contexts][context]
        multi_options = metadata["multi"][:contexts][context]
        if single_options && multi_options
          control_options = single_options[:options]
          policy_options = multi_options[:options]
          # iterate through policy options to see which is enabled and checked

          policy_options.each do |option|
            # This is a product or SKU, check if this option is available
            option[:is_available] = @policies_available.include?(option[:value])
            # Then check if this option is enabled
            option[:checked?] = @policies_enabled.include?(option[:value])
          end

          control_options.each do |option|
            # This is a single select, it will only be copilot_premium_request, check if multi-select is available
            if option[:value] == "multi"
              option[:is_available] = @policies_available.length > 1
              option[:checked?] = @is_multi_select_enabled
            elsif option[:value] == "true"
              option[:checked?] = @policies_enabled.include?(single_select_policy_name(tbb_enabled: tbb_enabled)) && !@is_multi_select_enabled
              option[:is_available] = true
            else
              option[:checked?] = !@policies_enabled.include?(single_select_policy_name(tbb_enabled: tbb_enabled)) && !@is_multi_select_enabled
              option[:is_available] = true
            end
          end

          # Build and return the policy hash
          result_policy = {
            title: multi_options[:title],
            description: multi_options[:description],
            options: policy_options,
            control_options: control_options
          }

          return T.let(result_policy, PolicyType)
        end
        nil
      end
    end

    sig { params(tbb_enabled: T::Boolean).returns(T::Hash[String, T.untyped]) }
    def policy_metadata(tbb_enabled:)
      Billing::OveragePolicyConfiguration.metadata_for(@name, tbb_enabled: tbb_enabled)
    end

    sig { params(tbb_enabled: T::Boolean).returns(String) }
    def single_select_policy_name(tbb_enabled:)
      if tbb_enabled
        Billing::OveragePolicyConfiguration::COPILOT_AI_UNIT
      else
        Billing::OveragePolicyConfiguration::COPILOT_PREMIUM_REQUEST
      end
    end

    sig { params(value: String).returns(T.nilable(String)) }
    def submit_path(value)
      if value == "multi"
        if request&.fullpath
          uri = URI.parse(request&.fullpath)
          params_hash = Rack::Utils.parse_nested_query(uri.query || "")
          params_hash["multi_select"] = "true"
          uri.query = params_hash.to_query
          uri.to_s
        else
          nil
        end
      elsif value == "true" || value == "false"
        enabled = value == "true"
        if @policies_available.length > 1
          policies = @policies_available.map do |policy_name|
            {
              type: policy_name == Billing::OveragePolicyConfiguration::SPARK ? Billing::OveragePolicyConfiguration::PRODUCT : Billing::OveragePolicyConfiguration::SKU,
              name: policy_name,
              enabled: value
            }
          end
          if business?
            policy_update_enterprise_billing_path(@entity, policies: policies, return_to: request&.fullpath)
          elsif organization?
            org_policy_update_organization_settings_billing_path(@entity, policies: policies, return_to: request&.fullpath)
          end
        else
          if business?
            policy_update_enterprise_billing_path(@entity, type: @overage_policy_type, name: @name, enabled: enabled, return_to: request&.fullpath)
          elsif organization?
            org_policy_update_organization_settings_billing_path(@entity, type: @overage_policy_type, name: @name, enabled: enabled, return_to: request&.fullpath)
          end
        end
      end
    end

    sig { returns(T::Boolean) }
    def should_enable_multi_select?
      if @policies_enabled.length != @policies_available.length && @policies_enabled.length > 0
        return true
      elsif params[:multi_select].present?
        return true
      end
      false
    end

    sig { params(value: String, enabled: T::Boolean).returns(T.nilable(String)) }
    def multi_select_submit_path(value:, enabled:)
      type = "sku"
      if value == "spark"
        type = "product"
      end
      if business?
        policy_update_enterprise_billing_path(@entity, type: type, name: value, enabled: enabled, return_to: request&.fullpath)
      elsif organization?
        org_policy_update_organization_settings_billing_path(@entity, type: type, name: value, enabled: enabled, return_to: request&.fullpath)
      end
    end

    sig { returns(String) }
    def link_text
      "Set a budget to control your maximum spend."
    end

    sig { returns(String) }
    def link_path
      enterprise_billing_budgets_path(@entity)
    end

    sig { returns(String) }
    def current_label
      current_policy = policy
      return "Unknown" unless current_policy
      current_policy[:enabled] ? "Enabled" : "Disabled"
    end

    private

    sig { returns(T::Boolean) }
    memoize def tbb_enabled_for_policy_entity?
      entity = policy_entity_for_tbb
      if entity.nil?
        false
      else
        billing_tbb_enabled?(entity)
      end
    end

    sig { returns(T.nilable(T.any(::Business, Organization))) }
    def policy_entity_for_tbb
      if enterprise_owned_organization?
        org_entity = T.cast(@entity, Organization)
        org_entity.business
      elsif business?
        T.cast(@entity, ::Business)
      elsif organization?
        T.cast(@entity, Organization)
      end
    end

    sig { returns(Billing::Platform::Api::Client) }
    memoize def billing_platform_client
      Billing::Platform::Api::Client.new
    end
  end
end
