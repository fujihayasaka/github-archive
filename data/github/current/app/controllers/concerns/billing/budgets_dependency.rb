# typed: strict
# frozen_string_literal: true

module Billing::BudgetsDependency
  extend T::Helpers

  include Billing::Platform::Api::Utils
  include BillingSettingsHelper
  include Billing::CopilotIapSubscription

  requires_ancestor { ApplicationController }

  abstract!

  sig { abstract.params(entity: ::Billing::Types::Account).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def enabled_products(entity); end

  sig { params(this_entity: ::Billing::Types::Account, is_stafftools_route: T.nilable(T::Boolean), layout: T.nilable(String)).void }
  def render_budgets(this_entity:, is_stafftools_route: false, layout: nil)
    selected_link = this_entity.is_a?(Business) ? :business_billing_vnext_budgets_alerts : :billing_vnext_budgets

    respond_to do |format|
      format.json do
        budgets = []
        budgets_response = billing_platform_client.get_all_budgets(customer_id: this_entity.customer&.id.to_s)

        if budgets_response.is_a?(Billing::Platform::Api::Error)
          return render json: { error: "Unable to query budgets" }, status: 500
        end

        budgets = budgets_response[:budgets]
        # only filter the budgets for org and enterprise customers
        if !is_stafftools_route && !this_entity.is_a?(User)
          budgets = filter_budget_by_role(budgets: budgets_response[:budgets], current_user: current_user, entity: this_entity)
        end

        payload = {
          copilotIapSubscription: this_entity.is_a?(User) ? copilot_iap_subscription?(this_entity) : false,
          adminRoles: admin_roles(this_entity),
          budgets: budgets,
          enabledProducts: enabled_products(this_entity),
          enabledSkus: enabled_skus(this_entity: this_entity),
          customer: customer_payload(this_entity),
          helpUrl: GitHub.help_url,
        }

        render json: { payload: payload }, status: 200
      end

      format.html do
        payload = {
          copilotIapSubscription: this_entity.is_a?(User) ? copilot_iap_subscription?(this_entity) : false,
          adminRoles: admin_roles(this_entity),
          enabledProducts: enabled_products(this_entity),
          enabledSkus: enabled_skus(this_entity: this_entity),
          showCopilotPremiumBanner: copilot_premium_overage_disabled?(this_entity),
          copilotPremiumPolicyLink: copilot_premium_policy_link(this_entity),
          customer: customer_payload(this_entity),
          helpUrl: GitHub.help_url,
          layout: layout
        }
        kwargs = {
          payload: payload,
          page_data: { selected_link: selected_link, sidebar: :billing_and_licensing },
          title: "Budgets",
        }

        if layout.present? && !is_stafftools_route
          kwargs.merge!(layout: layout)
        end

        render_react_app(**kwargs)
      end
    end
  rescue => e # rubocop:todo Lint/RescueException
    Failbot.report(e)
    render json: { error: "Unable to query budgets" }, status: 500
  end

  sig { params(this_entity: ::Billing::Types::Account).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def enabled_skus(this_entity:)
    response = billing_platform_client.get_all_pricing
    current_time = Time.now.to_i

    if response.is_a?(::Billing::Platform::Api::Error)
      []
    else
      skus = response[:pricings]
      if this_entity.is_a?(Business) && this_entity.seats_plan_type == "basic" || this_entity.is_a?(User) && !this_entity.is_a?(Organization)
        skus.reject! { |sku| sku[:sku] == "copilot_for_business" }
      end

      if this_entity.is_a?(Business) && this_entity.seats_plan_type == "basic" || this_entity.is_a?(User)
        skus.reject! { |sku| sku[:sku] == "copilot_enterprise" }
      end

      if this_entity.is_a?(Business) && this_entity.seats_plan_type != "basic" || this_entity.is_a?(Organization) || this_entity.is_a?(User)
        skus.reject! { |sku| sku[:sku] == "copilot_standalone" }
      end

      if !this_entity.advanced_security_products_bundled?
        skus.reject! { |sku| sku[:sku] == "ghas_licenses" }
      else
        skus.reject! { |sku| sku[:sku] == "ghas_secret_protection_licenses" || sku[:sku] == "ghas_code_security_licenses" }
      end

      unless this_entity.feature_flag_enabled?(:billing_enable_coding_agent_product, default: false)
        skus.reject! { |sku| sku[:sku] == "coding_agent_premium_request" }
      end

      skus.reject! { |sku| !sku[:effectiveAt].nil? && sku[:effectiveAt] > current_time }
      skus
    end
  end

  sig { params(audit_fields: T::Hash[Symbol, T.untyped], old_value: T.untyped, new_value: T.untyped, audit_key: Symbol, numeric: T::Boolean).void }
  def compare_and_add_field(audit_fields, old_value, new_value, audit_key, numeric: false)
    if numeric
      return unless old_value && new_value
      audit_fields[audit_key] = old_value if old_value.to_f != new_value.to_f
    else
      audit_fields[audit_key] = old_value if old_value.to_s != new_value.to_s
    end
  end

  sig { params(old_budget: T.nilable(T::Hash[String, T.untyped]), edit_budget_request: T.untyped).returns(T::Hash[Symbol, T.untyped]) }
  def build_audit_fields(old_budget, edit_budget_request)
    audit_fields = {}
    return audit_fields unless old_budget

    compare_and_add_field(audit_fields, old_budget["targetAmount"], edit_budget_request[:targetAmount], :old_target_amount, numeric: true)
    compare_and_add_field(audit_fields, old_budget.dig("key", "pricingTargetType"), edit_budget_request[:pricingTargetType], :old_pricing_target_type)
    compare_and_add_field(audit_fields, old_budget.dig("key", "pricingTargetId"), edit_budget_request[:pricingTargetId], :old_pricing_target_id)
    compare_and_add_field(audit_fields, old_budget["budgetLimitType"], edit_budget_request[:budgetLimitType], :old_budget_limit_type)
    compare_and_add_field(audit_fields, old_budget.dig("budgetAlerting", "willAlert"), edit_budget_request[:alertEnabled], :old_alert_enabled)
    compare_and_add_field(audit_fields, old_budget.dig("key", "targetType"), edit_budget_request[:targetType], :old_target_type)
    compare_and_add_field(audit_fields, old_budget.dig("key", "targetId"), edit_budget_request[:targetId], :old_target_id)

    audit_fields
  end

  sig { params(customer_id: String, uuid: String).returns(T.nilable(T::Hash[String, T.untyped])) }
  def fetch_old_budget(customer_id, uuid)
    response = billing_platform_client.get_budget_by_uuid(customer_id: customer_id, uuid: uuid)
    return nil if response.is_a?(Billing::Platform::Api::Error)
    obj = response[:budget]
    obj&.raw_budget_hash&.fetch("budget", nil)
  end

  sig { params(entity: ::Billing::Types::Account).returns(T::Boolean) }
  def copilot_premium_overage_disabled?(entity)
    return false unless entity.customer

    customer_id = T.must(entity.customer).id.to_s
    billing_client = billing_platform_client
    policy_response = billing_client.get_overage_policy(
      customer_id: customer_id,
      overage_policy_type: "sku",
      name: "copilot_premium_request",
      is_for_business: entity.is_a?(Business)
    )

    return false if policy_response.is_a?(Billing::Platform::Api::Error)

    # Check if overages is disabled
    enabled = policy_response[:overagePolicy][:enabled]
    !enabled
  rescue => e
    # If we can't determine the policy, assume overages are not disabled to avoid false banners
    Failbot.report(e)
    false
  end

  sig { params(entity: ::Billing::Types::Account).returns(String) }
  def copilot_premium_policy_link(entity)
    if entity.is_a?(Business)
      # Enterprise account
      "https://github.com/enterprises/#{entity.slug}/settings/copilot"
    elsif entity.is_a?(Organization)
      # Standalone organization
      "https://github.com/organizations/#{entity.display_login}/settings/copilot/policies"
    else
      # User account - should not show banner for users based on the requirements
      ""
    end
  end

  private

  sig { returns(Billing::Platform::Api::Client) }
  def billing_platform_client
    Billing::Platform::Api::Client.new
  end
end
