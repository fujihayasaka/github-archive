# typed: strict
# frozen_string_literal: true

class Stafftools::Users::Billing::UsageOverviewsController < Stafftools::Users::BillingController
  before_action :ensure_vnext_enabled

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

    render_react_app(
      payload: {
        customer: customer_payload(this_user),
        customer_selections: usage_customer_selections(this_user),
        period_selections: usage_period_selections,
        admin_roles: admin_roles(this_user),
        enabled_products: enabled_products(this_user),
        multi_tenant: GitHub.multi_tenant_enterprise?,
        budget_alert_details: [],
        page_data: { selected_link: :overview },
        title: "Billing Overview",
        layout: "organization_settings",
        taxDisclaimer: tax_disclaimer(this_user),
        copilotForIndividualsData: {
          subscriptionItem: subscription_item_payload(copilot_subscription_item),
          onFreeTier: Copilot::Public::User.new(T.cast(this_entity, User)).has_copilot_individual_free_access?,
        },
        copilot_premium_usage_report_enabled: copilot_premium_usage_report_enabled?(this_entity)
      },
    )
  end

  private

  sig { params(this_entity: ::Billing::Types::Account).returns(T::Boolean) }
  def copilot_premium_usage_report_enabled?(this_entity)
    # saving this_entity to a local variable to help Sorbet with type narrowing
    # in the case statement.
    entity = this_entity

    return false unless entity.feature_enabled?(:copilot_overages_usage_report)

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
end
