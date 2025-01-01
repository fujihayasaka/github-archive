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
        vnext_migration_date: is_legacy_report_an_option ? this_user.customer.vnext_migration_date.strftime("%b %d, %Y") : nil,
        min_custom_date: min_custom_date,
        copilot_premium_usage_report_enabled: copilot_premium_usage_report_enabled?(this_user),
        report_type_selections: report_type_selections,
        billing_coding_agent_enabled: billing_coding_agent_enabled?(this_user),
        billing_spark_enabled: billing_spark_enabled?(this_user),
        slug: this_user.display_login,
      },
      page_data: { selected_link: :usage },
      title: "Billing Usage",
    )
  end

  private

  sig { params(this_entity: ::Billing::Types::Account).returns(T::Boolean) }
  def copilot_premium_usage_report_enabled?(this_entity)
    # saving this_entity to a local variable to help Sorbet with type narrowing
    # in the case statement.
    entity = this_entity

    return false unless entity.feature_flag_enabled_or_raise?(:copilot_overages_usage_report) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage

    case (entity)
    when Organization
      Copilot::Organization.new(entity).can_export_premium_usage? && show_pru_option_on_usage_page?
    when User
      Copilot::User.new(entity).can_export_premium_usage? && show_pru_option_on_usage_page?
    else
      raise TypeError, "copilot_premium_usage_report_enabled? called on an unexpected entity type: #{entity.class}"
    end
  end

  sig { returns(T::Boolean) }
  def show_pru_option_on_usage_page?
    !FeatureFlag.vexi.enabled?(:pru_billing_page, this_user, default: false)
  end
end
