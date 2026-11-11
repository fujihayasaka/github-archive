# typed: strict
# frozen_string_literal: true

class Stafftools::Users::Billing::UsagesController < Stafftools::Users::BillingController
  T.unsafe(self).react_bundle_name = "billing-app"

  before_action :ensure_vnext_enabled
  include Billing::UsageDependency

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
                      ApplicationRecord::Ballast,
                      only: [:show]

  sig { void }
  def show
    is_legacy_report_an_option = this_user.customer.is_legacy_report_an_option?
    min_custom_date = min_custom_date(customer: this_user.customer)

    usage_selections_with_legacy_option = if is_legacy_report_an_option
      usage_selections_with_legacy_option = usage_report_selections.push(usage_report_legacy_selection)
      usage_selections_with_legacy_option = filter_period_selections(usage_selections_with_legacy_option, this_user.customer.vnext_migration_date)
    end

    migration_date = is_legacy_report_an_option ? this_user.customer.vnext_migration_date.strftime("%B %d, %Y") : nil
    report_type_selections = usage_report_type_selections(
      is_legacy_option: is_legacy_report_an_option,
      migration_date: migration_date,
      min_custom_date: min_custom_date
    )

    render_react_app(
      payload: {
        customer: customer_payload(this_user),
        customer_selections: usage_customer_selections(this_user),
        period_selections: usage_period_selections,
        admin_roles: admin_roles(this_user),
        group_selections: usage_group_selections(this_user),
        budget_alert_details: nil,
        layout: "organization_settings",
        usage_report_selections: usage_selections_with_legacy_option || usage_report_selections,
        enabled_products: enabled_products(this_user),
        current_user_email: current_user&.default_notification_email || "",
        min_custom_date: min_custom_date,
        report_type_selections: report_type_selections,
      },
      page_data: { selected_link: :usage },
      title: "Billing Usage",
    )
  end
end
