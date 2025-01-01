# typed: strict
# frozen_string_literal: true

class Stafftools::Users::Billing::UsageOverviewsController < Stafftools::Users::BillingController
  before_action :ensure_vnext_enabled
  before_action :ensure_supported_entity!

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
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
    add_client_feature_flag(
      [:billing_enable_coding_agent_product],
      entity: this_user,
    )

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
          onFreeTier: Copilot::Public::User.new(T.cast(this_entity, User)).has_copilot_individual_free_access?,
        },
        copilot_premium_usage_report_enabled: copilot_premium_usage_report_enabled?(this_entity),
        nextPaymentTileData: {
          nextPaymentDate: next_payment_due_date,
          meteredViaAzure: this_entity.customer&.metered_via_azure?,
          autoPayDisabled: this_entity.autopay_disabled_by_india_rbi?,
          overdue: this_entity.manual_payment_due_date&.past?,
          nextChargeAmount: next_charge_amount,
          rbiPaymentLink: org_bill_pay_new_path(organization_id: this_entity.display_login),
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

  sig { params(this_entity: ::Billing::Types::Account).returns(T::Boolean) }
  def copilot_premium_usage_report_enabled?(this_entity)
    # saving this_entity to a local variable to help Sorbet with type narrowing
    # in the case statement.
    entity = this_entity

    return false unless entity.feature_flag_enabled_or_raise?(:copilot_overages_usage_report) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage

    case (entity)
    when Organization
      Copilot::Organization.new(entity).can_export_premium_usage?
    when User
      Copilot::User.new(entity).can_export_premium_usage?
    else
      raise TypeError, "copilot_premium_usage_report_enabled? called on an unexpected entity type: #{entity.class}"
    end

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
