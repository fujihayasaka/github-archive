# typed: strict
# frozen_string_literal: true

class Stafftools::Users::Billing::UsageOverviewsController < Stafftools::Users::BillingController
  include Billing::TokenBasedBilling

  before_action :ensure_vnext_enabled
  before_action :ensure_supported_entity!

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Copilot,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    only: [:show]

  sig { returns(String) }
  def self.react_bundle_name
    "billing-app"
  end

  sig { void }
  def show
    return render_404 unless GitHub.billing_enabled?

    render_react_app(
      payload: {
        customer: customer_payload(this_user),
        customer_selections: usage_customer_selections(this_user),
        period_selections: usage_period_selections,
        admin_roles: admin_roles(this_user),
        enabled_products: enabled_products(this_user),
        multi_tenant: GitHub.multi_tenant_enterprise?,
        budget_alert_details: nil,
        page_data: { selected_link: :overview },
        title: "Billing Overview",
        layout: "organization_settings",
        taxDisclaimer: tax_disclaimer(this_user),
        copilotForIndividualsData: {
          subscriptionItem: subscription_item_payload(copilot_subscription_item),
          onFreeTier: Copilot::Public::User.for(T.cast(this_entity, User)).has_copilot_individual_free_access?,
        },
        show_preview_bill: true,
        is_token_based_billing_enabled: billing_tbb_enabled?(this_entity),
        billing_user_level_ai_units: billing_user_level_ai_units?(this_entity),
        nextPaymentTileData: {
          nextPaymentDate: next_payment_due_date,
          meteredViaAzure: this_entity.customer&.metered_via_azure?,
          autoPayDisabled: this_entity.autopay_disabled_by_india_rbi?,
          overdue: this_entity.manual_payment_due_date&.past?,
          nextChargeAmount: next_charge_amount,
          rbiPaymentLink: stafftools_rbi_payment_link,
          entityLogin: this_entity.display_login,
        },
        next_payment_card_enabled: this_entity.invoiced?,
      },
    )
  end

  private

  sig { void }
  def ensure_supported_entity!
    render_404 unless this_entity.is_a?(User) || this_entity.is_a?(Organization)
  end

  sig { returns(T.nilable(Billing::Public::SubscriptionItem)) }
  def copilot_subscription_item
    copilot_type_product_identifier = Billing::Public::Product::ProductIdentifier.new(product_type: Billing::ProductUUID::COPILOT_PRODUCT_TYPE)
    Billing::Public::SubscriptionItem.all_active(account: this_entity, product: copilot_type_product_identifier).value { [] }.first
  end

  sig { returns(T.nilable(String)) }
  def next_payment_due_date
    return nil unless this_entity.is_a?(User)
    return nil unless T.cast(this_entity, User).next_payment_due_on
    return "Today" if this_entity.next_billing_date == Date.today
    this_entity.next_billing_date&.strftime("%b %d, %Y")
  end

  sig { returns(String) }
  def stafftools_rbi_payment_link
    login = this_entity.display_login
    if this_entity.autopay_disabled_by_india_rbi? &&
        FeatureFlag.vexi.enabled?(:billing_india_rbi_recurring_payments, this_entity, default: false)
      org_card_setup_new_path(organization_id: login)
    else
      org_bill_pay_new_path(organization_id: login)
    end
  end

  sig { returns(T.untyped) }
  def next_charge_amount
    case this_entity
    when Organization, User
      T.cast(this_entity, User).next_charge_amount
    else
      nil
    end
  end
end
