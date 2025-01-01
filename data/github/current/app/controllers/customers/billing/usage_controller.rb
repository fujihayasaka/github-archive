# typed: strict
# frozen_string_literal: true

class Customers::Billing::UsageController < Customers::BillingController
  include Billing::UsageDependency
  T.unsafe(self).react_bundle_name = "billing-app"

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

  sig { void }
  def show
    notification = Billing::Notifications::CustomerBudgetsNotifications.new(owner: this_entity, actor: current_user)
    banners = notification.budget_threshold_banners(actor: current_user)

    usage_selections_with_legacy_option = usage_report_selections
    if this_entity.customer&.is_legacy_report_an_option?
      usage_selections_with_legacy_option.push(usage_report_legacy_selection)
      usage_selections_with_legacy_option = filter_period_selections(usage_selections_with_legacy_option, this_entity.customer&.billing_platform_enabled_product&.migration_date)
    end

    render_react_app(
      payload: {
        customer: customer_payload(this_entity),
        customer_selections: usage_customer_selections(this_entity),
        period_selections: usage_period_selections,
        group_selections: usage_group_selections(this_entity),
        disable_usage_reports: this_entity.feature_enabled?(:billing_platform_disable_usage_reports),
        billing_platform_enabled_products: enabled_products.map { |product| product[:friendlyProductName] },
        usage_report_selections: usage_selections_with_legacy_option,
        vnext_migration_date: this_entity.customer&.is_legacy_report_an_option? ? this_entity.customer&.readable_vnext_migration_date : nil,
        current_user_email: current_user&.default_notification_email,
        budget_alert_details: banners.map do |banner|
          {
            text: banner.text,
            variant: banner.variant.to_s,
            dismissible: banner.dismissible?,
            dismiss_link: banner.dismissal_path,
            budget_id: banner.budget_uuid,
          }
        end,
        min_custom_date: min_custom_date(customer: T.must(this_entity.customer)),
        copilot_premium_usage_report_enabled: copilot_premium_usage_report_enabled?
      },
      page_data: { selected_link: :billing_vnext_usage },
      title: "Billing Usage",
      layout: customer_billing_page_layout,
    )
  end

  private

  sig do
    params(billing_items: T.nilable(T::Array[T::Hash[T.untyped, T.untyped]]))
      .returns(T::Array[String])
  end
  def json_billing_items(billing_items)
    return [] if billing_items.nil?

    billing_items.map { |item| Billing::Platform::Api::UsageLineItem.new(item).to_json }
  end

  sig { returns(T::Boolean) }
  def copilot_premium_usage_report_enabled?
    # saving this_entity to a local variable to help Sorbet with type narrowing
    # in the case statement.
    entity = this_entity

    case (entity)
    when Organization
      Copilot::Organization.new(entity).can_export_premium_usage?
    when User
      Copilot::User.new(entity).can_export_premium_usage?
    else
      raise TypeError, "copilot_premium_usage_report_enabled? called on an unexpected entity type: #{entity.class}"
    end
  end
end
