# typed: strict
# frozen_string_literal: true

module Billing::PremiumRequestsUsageDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  include BillingSettingsHelper
  include Billing::UsageDependency
  include Billing::ProductsDependency
  include Billing::MultiUserBudgetCheck
  include Customers::Concerns::BillingPayload

  requires_ancestor { ApplicationController }

  abstract!

  sig { params(entity: ::Billing::Types::Account, current_user: User, is_stafftools_route: T::Boolean).void }
  def render_premium_requests_usage(entity:, current_user:, is_stafftools_route: false)
    render_options = {
      payload: {
        customer: customer_payload(entity),
        customer_selections: usage_customer_selections(entity),
        group_selections: premium_requests_usage_group_selections(entity, current_user, is_stafftools_route: is_stafftools_route),
        period_selections: premium_requests_usage_period_selections,
        current_user_email: current_user.default_notification_email,
        can_request_all_usage: entity.is_a?(Business) ? entity.owner?(current_user) || entity.billing_manager?(current_user) : true,
        is_copilot_standalone: entity.is_a?(Business) && entity.is_copilot_standalone?,
        usage_report_selections: premium_request_usage_report_selections,
        disable_usage_reports: FeatureFlag.vexi.enabled?(:disable_billing_usage_reports, entity, default: false),
        min_custom_date: min_custom_date(customer: T.must(entity.customer), premium_request_report: true),
        report_type_selections: premium_request_usage_report_type_selections(entity: entity),
        has_multi_user_customer_budget: entity.is_a?(Business) ? has_multi_user_customer_budget?(entity) : false,
      },
      page_data: { selected_link: entity.is_a?(Business) ? :business_billing_vnext_premium_requests_usage : :billing_vnext_premium_requests_usage, sidebar: :billing_and_licensing },
      layout: react_layout(entity, is_stafftools_route),
      title: "Premium request analytics",
    }

    render_react_app(**render_options)
  end

  sig { params(entity: ::Billing::Types::Account, current_user: User, is_stafftools_route: T::Boolean).returns(T::Array[{ type: Integer, displayText: String }]) }
  def premium_requests_usage_group_selections(entity, current_user, is_stafftools_route: false)
    if entity.user?
      return [
        { type: BillingPlatform::Base::UsageGroupBy::GroupByModel, displayText: "Models" },
        { type: BillingPlatform::Base::UsageGroupBy::GroupByProduct, displayText: "Products" },
        { type: BillingPlatform::Base::UsageGroupBy::NoGroupBy, displayText: "None" }
      ]
    end

    selections = [
      { type: BillingPlatform::Base::UsageGroupBy::GroupByModel, displayText: "Models" },
      { type: BillingPlatform::Base::UsageGroupBy::GroupByProduct, displayText: "Products" },

    ]

    if entity.is_a?(Organization)
      selections.insert(1, { type: BillingPlatform::Base::UsageGroupBy::GroupByUser, displayText: "Users" })
    end

    if entity.is_a?(Business)
      if !entity.is_copilot_standalone?
        selections << { type: BillingPlatform::Base::UsageGroupBy::GroupByOrganization, displayText: "Organizations" }
      end

      if entity.owner?(current_user) || entity.billing_manager?(current_user) || is_stafftools_route
        selections.insert(1, { type: BillingPlatform::Base::UsageGroupBy::GroupByUser, displayText: "Users" })
      end
      selections << { type: BillingPlatform::Base::UsageGroupBy::GroupByCostCenter, displayText: "Cost centers" }
    end

    selections << { type: BillingPlatform::Base::UsageGroupBy::NoGroupBy, displayText: "None" }

    selections
  end

  sig { returns(T::Array[{ type: Integer, displayText: String }]) }
  def premium_requests_usage_period_selections
    current_time = Time.now.utc
    selections = []

    selections << { type: USAGE_PERIOD[:this_month], displayText: "Current month" }
    selections << { type: USAGE_PERIOD[:last_month], displayText: "Last month" }
    selections << { type: USAGE_PERIOD[:this_year], displayText: "This year (#{current_time.year})" }

    # Only show "last year" if current year is >= 2026
    if current_time.year >= 2026
      selections << { type: USAGE_PERIOD[:last_year], displayText: "Last year (#{current_time.year - 1})" }
    end

    selections
  end

  sig { params(entity: ::Billing::Types::Account, is_stafftools_route: T::Boolean).void }
  def ensure_pru_page_enabled(entity:, is_stafftools_route: false)
    return if is_stafftools_route
    render_404 if should_exclude_copilot_product?(entity)
  end

  sig {  params(entity: ::Billing::Types::Account, is_stafftools_route: T::Boolean).returns(T.any(Symbol, String)) }
  def react_layout(entity, is_stafftools_route)
    if is_stafftools_route
      :default
    elsif entity.is_a?(Business)
      "react_business"
    elsif entity.is_a?(Organization)
      "organization_settings"
    else
      "user_settings"
    end
  end
end
