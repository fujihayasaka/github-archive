# typed: true
# frozen_string_literal: true

class Customers::BillingController < ApplicationController
  include ApplicationController::VerifiedFetchDependency
  include BillingSettingsHelper
  include Billing::Platform::Api::Utils
  include Billing::CopilotIapSubscription
  include Businesses::Concerns::BusinessAccess
  include Customers::Concerns::BillingPayload
  include GitHub::Memoizer
  include OrganizationsHelper
  include Billing::BillingChecksDependency
  include Billing::ProductsDependency
  include Billing::TrustTierDependency
  include Billing::TokenBasedBilling

  T.unsafe(self).react_bundle_name = "billing-app"
  stylesheet_bundle :billing

  before_action :ensure_actor_access
  before_action do
    T.bind(self, Customers::BillingController)
    ensure_vnext_enabled(entity: this_entity)
  end
  before_action :ensure_customer

  depends_on_clusters ApplicationRecord::Billing,
                      ApplicationRecord::Collab,
                      ApplicationRecord::Configurations,
                      ApplicationRecord::Copilot,
                      ApplicationRecord::IamAbilities,
                      ApplicationRecord::Mysql1,
                      ApplicationRecord::Mysql2,
                      ApplicationRecord::Mysql5,
                      ApplicationRecord::NotificationsEntries,
                      ApplicationRecord::Repositories,
                      only: [:show]

  def show
    begin
      notification = Billing::Notifications::CustomerBudgetsNotifications.new(owner: this_entity, actor: current_user)
      banner = notification.combined_budget_threshold_banner(actor: current_user)
    rescue => e
      Failbot.report(e)
      GitHub.dogstats.increment("billing_platform.budget_banner_error")
      banner = nil
    end

    customer = customer_payload(this_entity, plan_pricing: plan_product_pricing)
    render_react_app(
      payload: {
        customer: customer,
        customer_selections: usage_customer_selections(this_entity),
        period_selections: usage_period_selections,
        admin_roles: admin_roles(this_entity),
        enabled_products: enabled_products(this_entity),
        budget_alert_details: banner&.to_payload_hash,
        showTrustTierBanner: show_trust_tier_banner?(this_entity),
        taxDisclaimer: tax_disclaimer(this_entity),
        copilotForIndividualsData: {
          subscriptionItem: subscription_item_payload(copilot_subscription_item, product_pricing: copilot_product_pricing),
          onFreeTier: this_entity.is_a?(User) ? Copilot::Public::User.for(T.cast(this_entity, User)).has_copilot_individual_free_access? : false,
        },
        nextPaymentTileData: next_payment_tile_data,
        copilotIapSubscription: this_entity.is_a?(User) ? copilot_iap_subscription?(T.cast(this_entity, User)) : false,
        billingAddCostCenterDescription: FeatureFlag.vexi.enabled?(:billing_add_cost_center_description, this_entity, default: false),
        show_preview_bill: bill_preview_enabled?(this_entity),
        is_token_based_billing_enabled: billing_tbb_enabled?(this_entity),
        billing_user_level_ai_units: billing_user_level_ai_units?(this_entity),
      },
      page_data: { selected_link: :billing_vnext_overview },
      title: "Billing Overview",
      layout: customer_billing_page_layout,
    )
  end

  private

  sig { returns(::Billing::Types::Account) }
  memoize def this_entity
    return this_business if enterprise_path?
    return this_organization if organization_path?
    this_user
  end
  helper_method :this_entity

  memoize def this_organization
    Organization.find_by(login: params[:organization_id])
  end
  alias_method :current_organization, :this_organization

  memoize def this_user
    current_user
  end
  helper_method :this_user

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def next_payment_tile_data
    {
      nextPaymentDate: next_payment_due_date,
      meteredViaAzure: this_entity.customer&.metered_via_azure?,
      autoPayDisabled: this_entity.autopay_disabled_by_india_rbi?,
      overdue: this_entity.manual_payment_due_date&.past?,
      rbiPaymentLink: rbi_payment_link,
    }
  end

  def next_payment_due_date
    entity = this_entity
    unless entity.is_a?(User)
      raise NotImplementedError, "#{this_entity.class} is not supported in this controller"
    end

    return nil unless entity.next_payment_due_on || entity.manual_payment_due_date
    next_billing_date = entity.manual_payment_due_date || entity.next_billing_date
    return "Today" if next_billing_date == Date.today
    next_billing_date&.strftime("%b %d, %Y")
  end

  def rbi_payment_link
    use_card_setup = this_entity.autopay_disabled_by_india_rbi? &&
      FeatureFlag.vexi.enabled?(:billing_india_rbi_recurring_payments, this_entity, default: false)

    if this_entity.user?
      use_card_setup ? card_setup_new_path : bill_pay_new_path
    else
      login = T.cast(this_entity, Organization).display_login
      use_card_setup ? org_card_setup_new_path(organization_id: login) : org_bill_pay_new_path(organization_id: login)
    end
  end

  def target_for_conditional_access
    return this_business if enterprise_path? && this_business
    return this_organization if organization_path? && this_organization
    return this_user if individual_path? && this_user
    # CAP is not needed if there is no logged in user. We'd 404 in that case.
    :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess

    # Should this happen it will raise ArgumentError: malformed request
  end

  def customer_billing_page_layout
    return "layouts/react_business" if enterprise_path?
    return "layouts/organization_settings" if organization_path?
    "layouts/user_settings"
  end

  def usage_filter_params
    params.except(:organization_id, :enterprise_slug).permit(:customer_id, :period, :product, :sku, :query, :group, :page, :chart_type, :unit_type).to_h.symbolize_keys
  end

  def ensure_actor_access
    return render_404 unless logged_in?
    return business_access_required(allow_org_owners: true) if enterprise_path?
    render_404 if organization_path? && !org_billing_manageable?(this_organization)
  end

  def ensure_customer
    render_404 unless this_entity.customer&.persisted?
  end

  def ensure_billing_manager_and_member_of_org
    organization_path? && this_organization.billing_manager?(current_user) && this_organization.member?(current_user)
  end

  def ensure_billing_manager_or_owner_for_org
    true if org_admin?(this_organization)
  end

  def return_404_if_not_owner_or_member_billing_manager_of_organization
    if organization_path? && !(org_admin?(this_organization) || ensure_billing_manager_and_member_of_org)
      render_404
    end
  end

  # The GraphQL query that powers the Repository picker enforces CAP filtering and we need to prompt the user
  # to authenticate in order to see all of their repositories. Only Org owners are able to set budgets and cost centers
  # on repositories which is why we limit the viewer role to "owner".
  memoize def set_organizations
    return this_business.filtered_organizations(viewer: current_user, viewer_role: "owner") if enterprise_path?
    return [this_organization] if organization_path? && org_billing_manageable?(this_organization)
    return this_user.owned_organizations if individual_path?
    []
  end

  memoize def enterprise_path?
    T.must(request).path.start_with?("/enterprises/")
  end

  memoize def organization_path?
    T.must(request).path.start_with?("/organizations/")
  end

  memoize def individual_path?
    T.must(request).path.start_with?("/settings/")
  end

  sig { returns(T::Boolean) }
  def is_org?
    this_entity.is_a?(Organization)
  end

  sig { returns(String) }
  def react_layout
    is_org? ? "organization_settings" : "user_settings"
  end

  sig { returns(String) }
  def customer_id
    T.must(this_entity.customer).id.to_s
  end

  sig { returns(T.nilable(Billing::Public::SubscriptionItem)) }
  memoize def copilot_subscription_item
    return nil unless this_entity.is_a?(User)
    copilot_type_product_identifier = Billing::Public::Product::ProductIdentifier.new(product_type: Billing::ProductUUID::COPILOT_PRODUCT_TYPE)
    Billing::Public::SubscriptionItem.all_active(account: this_entity, product: copilot_type_product_identifier).value { [] }.first
  end

  sig { returns(T.nilable(Billing::ProductPricing)) }
  def copilot_product_pricing
    item = copilot_subscription_item
    return nil unless item
    return nil unless this_entity.is_a?(User)

    Billing::ProductPricing.for_subscription_item(subscription_item: item, account: T.cast(this_entity, User))
  end

  sig { returns(T.nilable(Billing::ProductPricing)) }
  def plan_product_pricing
    entity = this_entity
    return nil unless entity.is_a?(User) || entity.is_a?(Organization)

    Billing::ProductPricing.for_plan(account: T.cast(entity, T.any(User, Organization)))
  end
end
