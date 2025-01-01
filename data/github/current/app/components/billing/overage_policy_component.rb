# typed: strict
# frozen_string_literal: true

module Billing
  class OveragePolicyComponent < ApplicationComponent
    sig do params(
      entity: T.any(User, Business),
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
    end

    OptionType = T.type_alias do
      {
        label: String,
        description: String,
        value: T::Boolean,
        checked?: T::Boolean,
      }
    end

    PolicyType = T.type_alias do
      {
        title: String,
        description: String,
        enabled: T::Boolean,
        options: T::Array[OptionType],
      }
    end

    sig { returns(T::Boolean) }
    def has_permission_to_view_policy?
      if @entity.is_a?(Business) || @entity.is_a?(Organization)
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

    sig { returns(T.nilable(PolicyType)) }
    def configure_overage_policy
      # We aren't currently supporting changing the policy for enterprise-owned orgs
      if @entity.delegate_billing_to_business?
        return nil
      end

      policy_response = billing_platform_client.get_overage_policy(customer_id: @entity.customer&.id, overage_policy_type: @overage_policy_type, name: @name, is_for_business: @entity.is_a?(Business))

      # Render nothing if billing platform response isn't working
      if policy_response.is_a?(Billing::Platform::Api::Error)
        Failbot.report(policy_response)
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:503", "operation:billing/get_overage_policy"])
        nil
      else
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:200", "operation:billing/get_overage_policy"])
        # See if overages is set on params, if so, use that to override the policy response
        # This is useful for the update action where we want to reflect the change immediately
        # without waiting for the billing platform to update
        is_enabled = false
        enabled_str = policy_response[:overagePolicy][:enabled].nil? ? "false" : policy_response[:overagePolicy][:enabled].to_s
        if params[:overages].present?
          is_enabled = params[:overages] == "true"
        else
          is_enabled = enabled_str == "true"
        end

        if @overage_policy_type == "sku" && @name == "copilot_premium_request"
          if @entity.is_a?(Business)
            return {
              title: "Premium request paid usage",
              description: "When enabled, all organizations in your enterprise will be charged for premium requests that exceed their included usage. ",
              enabled: is_enabled,
              options: menu_items(is_enabled)
            }
          else
            return {
              title: "Premium request paid usage",
              description: "When enabled, your organization will be charged for premium requests that exceed your included usage. ",
              enabled: is_enabled,
              options: menu_items(is_enabled)
            }
          end
        end
      end
      nil
    end

    sig { params(currently_enabled: T::Boolean).returns(T::Array[OptionType]) }
    def menu_items(currently_enabled)
      if @overage_policy_type == "sku" && @name == "copilot_premium_request"
        if @entity.is_a?(Business)
          return [
            {
              label: "Enabled",
              description: "Your organizations will be charged for premium requests that exceed your included usage. Organizations can set a budget to control their maximum spend.",
              value: true,
              checked?: currently_enabled,
            },
            {
              label: "Disabled",
              description: "Your organizations will not be charged for premium request overages. This setting is controlled at the enterprise level.",
              value: false,
              checked?: !currently_enabled,
            }
          ]
        else
          return [
            {
              label: "Enabled",
              description: "Your organization will be charged for premium requests that exceed your included usage.",
              value: true,
              checked?: currently_enabled,
            },
            {
              label: "Disabled",
              description: "Your organization will not be charged for premium request overages.",
              value: false,
              checked?: !currently_enabled,
            }
          ]
        end
      end
      []
    end

    sig { params(enabled: T::Boolean).returns(T.nilable(String)) }
    def submit_path(enabled)
      if @entity.is_a?(Business)
        policy_update_enterprise_billing_path(@entity, type: @overage_policy_type, name: @name, enabled: enabled, return_to: request&.fullpath)
      elsif @entity.is_a?(Organization)
        org_policy_update_organization_settings_billing_path(@entity, type: @overage_policy_type, name: @name, enabled: enabled, return_to: request&.fullpath)
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

    private

    sig { returns(Billing::Platform::Api::Client) }
    def billing_platform_client
      Billing::Platform::Api::Client.new
    end
  end
end
