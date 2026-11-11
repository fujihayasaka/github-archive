# typed: strict
# frozen_string_literal: true

module Billing::BudgetsDependency
  extend T::Helpers

  include Billing::Platform::Api::Utils
  include BillingSettingsHelper
  include Billing::CopilotIapSubscription
  include Billing::UsageDependency
  include Customers::Concerns::BillingPayload
  include AvatarHelper
  include Billing::TokenBasedBilling

  requires_ancestor { ApplicationController }

  abstract!

  ALLOWED_BUDGET_TYPES = T.let(%w[premium_requests].freeze, T::Array[String])
  ALLOWED_BUDGET_SCOPES = T.let(%w[multi_user_customer].freeze, T::Array[String])

  sig { abstract.params(entity: ::Billing::Types::Account).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def enabled_products(entity); end

  sig { params(this_entity: ::Billing::Types::Account, is_stafftools_route: T.nilable(T::Boolean), layout: T.nilable(String), pagination: T.nilable(T::Hash[Symbol, T.untyped])).void }
  def render_budgets(this_entity:, is_stafftools_route: false, layout: nil, pagination: nil)
    selected_link = this_entity.is_a?(Business) ? :business_billing_vnext_budgets_alerts : :billing_vnext_budgets

    tbb_enabled = billing_tbb_enabled?(this_entity)

    # Forward dotcom's authoritative TBB decision to billing-platform for individual user
    tbb_override = (this_entity.is_a?(User) && this_entity.user?) ? tbb_enabled : nil

    respond_to do |format|
      format.json do
        budgets = []

        if paginated_budgets_request?(this_entity, pagination)
          pagination = T.must(pagination)
          # Pass exclude_scope for all account types when provided

          is_only_org_admin = this_entity.is_a?(Business) &&
                        (this_entity.user_is_owner_of_owned_org?(current_user) && !this_entity.billing_manager?(current_user) &&
                        !this_entity.owner?(current_user))

          target_org_ids = (current_user&.owned_organization_ids & this_entity.organization_ids).map(&:to_s)

          target_repo_ids = if is_only_org_admin
            Organization.includes(:repositories).where(id: target_org_ids).flat_map do |org|
              repos = org.repositories
              current_user.associated_repository_ids(repository_ids: repos.map(&:id)).map(&:to_s)
            end
          else
            []
          end

          budget_params = {
            customer_id: this_entity.customer&.id.to_s,
            page: pagination[:page],
            page_size: pagination[:page_size],
            scope: pagination[:scope],
            use_remote_cache: true,
            feature_flag_target: this_entity,
          }
          budget_params[:use_token_based_billing] = tbb_override unless tbb_override.nil?

          budget_params[:exclude_scope] = pagination[:exclude_scope] if pagination[:exclude_scope]

          if multi_scope_budgets_enabled?(this_entity)
            if pagination[:scopes].present? && pagination[:exclude_scopes].present?
              return render json: { error: "cannot specify both scopes and exclude_scopes" }, status: :unprocessable_entity
            end

            budget_params[:scopes] = pagination[:scopes] if pagination[:scopes].present?
            budget_params[:exclude_scopes] = pagination[:exclude_scopes] if pagination[:exclude_scopes].present?
          end

          if !budget_params[:scope].present? && !budget_params[:scopes].present?
            budget_params[:filtered_orgs] = target_org_ids if is_only_org_admin
            budget_params[:filtered_repos] = target_repo_ids if is_only_org_admin
          end

          budget_params[:include_total_count] = false if is_only_org_admin

          budgets_response = billing_platform_client.get_all_budgets(**budget_params)
        else
          non_paginated_params = {
            customer_id: this_entity.customer&.id.to_s,
            use_remote_cache: true,
            feature_flag_target: this_entity,
          }
          non_paginated_params[:use_token_based_billing] = tbb_override unless tbb_override.nil?

          budgets_response = billing_platform_client.get_all_budgets(**non_paginated_params)
        end

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
          includedUsageNotificationCustomer: fetch_included_usage_notification_customer(this_entity),
          consumedCopilotLicenses: consumed_copilot_licenses_for_entity(this_entity),
          multiScopeBudgetsEnabled: multi_scope_budgets_enabled?(this_entity),
          is_token_based_billing_enabled: tbb_enabled,
        }

        if this_entity.feature_flag_enabled?(:billing_budget_pagination_enabled, default: false) &&
          pagination.present? && budgets_response.is_a?(Hash)
          payload[:has_next_page] = budgets_response[:has_next_page] if budgets_response.key?(:has_next_page)
          payload[:total_count] = budgets_response[:total_count] if budgets_response.key?(:total_count)
          payload[:billing_budget_count_cache_enabled] = this_entity.feature_flag_enabled?(:billing_budget_count_cache, default: false)
        end

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
          layout: layout,
          includedUsageNotificationCustomer: fetch_included_usage_notification_customer(this_entity),
          consumedCopilotLicenses: consumed_copilot_licenses_for_entity(this_entity),
          multiScopeBudgetsEnabled: multi_scope_budgets_enabled?(this_entity),
          is_token_based_billing_enabled: tbb_enabled,
        }

        if this_entity.is_a?(User)
          copilot_user = Copilot::User.new(this_entity)
          if copilot_user.consumptive_user?
            payload[:copilot_trust_tier_limit_hit_banner] = budgets_trust_tier_limit_hit_banner_payload(copilot_user)
          end
        end
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
  rescue => e
    Failbot.report(e)
    render json: { error: "Unable to query budgets" }, status: 500
  end

  sig { params(this_entity: ::Billing::Types::Account, is_stafftools_route: T.nilable(T::Boolean), layout: T.nilable(String)).void }
  def render_multi_user_budget(this_entity:, is_stafftools_route: false, layout: nil)
    customer_id = this_entity.customer&.id.to_s
    budget_uuid = params[:id].to_s

    budget_response = billing_platform_client.get_budget_by_uuid(customer_id: customer_id, uuid: budget_uuid)

    if budget_response.is_a?(Billing::Platform::Api::Error)
      return render json: { error: "Unable to fetch budget" }, status: 500
    end

    budget = budget_response[:budget]
    budget_threshold_summary = budget.multi_user_budget_threshold_summary

    consumed_copilot_licenses = consumed_copilot_licenses_for_entity(this_entity)

    selected_link = this_entity.is_a?(Business) ? :business_billing_vnext_budgets_alerts : :billing_vnext_budgets

    respond_to do |format|
      format.json do
        payload = {
          budget: budget.as_json,
          customer: customer_payload(this_entity),
          consumedCopilotLicenses: consumed_copilot_licenses,
          budgetThresholdsSummary: budget_threshold_summary,
          adminRoles: admin_roles(this_entity),
          current_user_email: current_user&.default_notification_email,
          disable_usage_reports: FeatureFlag.vexi.enabled?(:disable_billing_usage_reports, this_entity, default: false),
          min_custom_date: min_custom_date(customer: T.must(this_entity.customer), premium_request_report: true),
          report_type_selections: premium_request_usage_report_type_selections(entity: this_entity),
          is_token_based_billing_enabled: billing_tbb_enabled?(this_entity),
        }

        render json: { payload: payload }, status: 200
      end
      format.html do
        payload = {
          budget: budget.as_json,
          customer: customer_payload(this_entity),
          consumedCopilotLicenses: consumed_copilot_licenses,
          budgetThresholdsSummary: budget_threshold_summary,
          adminRoles: admin_roles(this_entity),
          current_user_email: current_user&.default_notification_email,
          disable_usage_reports: FeatureFlag.vexi.enabled?(:disable_billing_usage_reports, this_entity, default: false),
          min_custom_date: min_custom_date(customer: T.must(this_entity.customer), premium_request_report: true),
          report_type_selections: premium_request_usage_report_type_selections(entity: this_entity),
          is_token_based_billing_enabled: billing_tbb_enabled?(this_entity),
        }
        kwargs = {
          payload: payload,
          page_data: { selected_link: selected_link, sidebar: :billing_and_licensing },
          title: "Multi User Budget",
        }
        if layout.present? && !is_stafftools_route
          kwargs.merge!(layout: layout)
        end
        render_react_app(**kwargs)
      end
    end
  rescue => e
    Failbot.report(e)
    render json: { error: "Unable to query budgets" }, status: 500
  end

  sig { params(copilot_user: Copilot::User).returns(T.nilable(Copilot::TrustTierLimitHitBannerPayload::Payload)) }
  def budgets_trust_tier_limit_hit_banner_payload(copilot_user)
    Copilot::TrustTierLimitHitBannerPayload.build(
      copilot_user: copilot_user,
      billing_platform_client: billing_platform_client,
      time_zone: copilot_user.user_object.time_zone,
    )
  end

  sig { params(this_entity: ::Billing::Types::Account).void }
  def render_multi_user_budget_states(this_entity:)
    customer_id = this_entity.customer&.id.to_s
    budget_uuid = params[:budget_uuid].to_s

    page = params[:page].presence&.to_i
    page_size = params[:page_size].presence&.to_i
    sort_order = params[:sort_order].presence&.to_i

    # Resolve username to user ID for user search
    user_id = nil
    if params[:username].present?
      user = User.find_by(login: params[:username])
      user_id = user&.id
    end

    threshold_lower_bound = params[:threshold_lower_bound].presence&.to_i
    threshold_upper_bound = params[:threshold_upper_bound].presence&.to_i

    # Restrict to org admin's organizations if they are an org admin but not an enterprise owner/billing manager
    filtered_orgs = nil
    if this_entity.is_a?(Business)
      is_only_org_admin = this_entity.user_is_owner_of_owned_org?(current_user) &&
        !this_entity.billing_manager?(current_user) &&
        !this_entity.owner?(current_user)

      if is_only_org_admin
        filtered_orgs = (current_user&.owned_organization_ids & this_entity.organization_ids).map(&:to_s)
      end
    end

    response = billing_platform_client.get_multi_user_budget_states(
      customer_id: customer_id,
      budget_uuid: budget_uuid,
      page: page,
      page_size: page_size,
      sort_order: sort_order,
      user_id: user_id,
      threshold_lower_bound: threshold_lower_bound,
      threshold_upper_bound: threshold_upper_bound,
      filtered_orgs: filtered_orgs,
    )

    if response.is_a?(Billing::Platform::Api::Error)
      return render json: { error: "Unable to fetch user budget states" }, status: 500
    end

    # Enrich user states with display names and avatar URLs from GitHub user records.
    user_states = response[:user_states]
    if user_states.present?
      user_ids = user_states.map { |us| us[:userId] }.compact

      if FeatureFlag.vexi.enabled?(:billing_multi_user_customer_search_filter, this_entity, default: false)
        # Restrict to users that are members of the enterprise so we never expose data
        # about unrelated accounts that may share an id with a usage row.
        lookup_ids = if this_entity.is_a?(Business)
          this_entity.admin_and_organization_member_ids(actor_ids: user_ids.map(&:to_i)).map(&:to_s).to_set
        else
          user_ids.map(&:to_s).to_set
        end

        users_by_id = User.where(id: lookup_ids.to_a).index_by { |u| u.id.to_s }

        user_states = user_states.select { |us| lookup_ids.include?(us[:userId].to_s) }.map do |us|
          github_user = users_by_id[us[:userId].to_s]
          enriched = us.dup
          if github_user
            enriched[:displayName] = github_user.display_login
            enriched[:avatarUrl] = avatar_url_for(github_user, 20)
          end
          enriched
        end
      else
        users_by_id = User.where(id: user_ids).index_by { |u| u.id.to_s }

        user_states = user_states.map do |us|
          github_user = users_by_id[us[:userId].to_s]
          enriched = us.dup
          if github_user
            enriched[:displayName] = github_user.display_login
            enriched[:avatarUrl] = avatar_url_for(github_user, 20)
          end
          enriched
        end
      end
    end

    render json: { payload: {
      user_states: user_states,
      has_next_page: response[:has_next_page],
      total_count: response[:total_count],
    } }, status: 200
  rescue => e
    Failbot.report(e)
    render json: { error: "Unable to query user budget states" }, status: 500
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

      unless this_entity.feature_flag_enabled?(:billing_enable_code_review_sku, default: false)
        skus.reject! { |sku| sku[:sku] == "code_review_premium_request" }
      end

      tbb_enabled = if this_entity.is_a?(User) && this_entity.user?
        Copilot::User.new(this_entity).use_token_based_billing?
      else
        billing_tbb_enabled?(this_entity)
      end

      unless tbb_enabled
        skus.reject! { |sku| sku[:sku] == "copilot_ai_unit" }
      end

      unless tbb_enabled
        skus.reject! { |sku| sku[:sku] == "coding_agent_ai_unit" }
      end

      unless tbb_enabled
        skus.reject! { |sku| sku[:sku] == "spark_ai_unit" }
      end

      if tbb_enabled
        skus.reject! { |sku| %w[copilot_premium_request coding_agent_premium_request spark_premium_request].include?(sku[:sku]) }
      end

      unless this_entity.feature_flag_enabled?(:billing_enable_sandbox_product, default: false)
        skus.reject! { |sku| %w[sandbox_linux sandbox_memory sandbox_snapshot].include?(sku[:sku]) }
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
    compare_and_add_field(audit_fields, old_budget["excludeCostCenterUsage"], edit_budget_request[:excludeCostCenterUsage], :old_exclude_cost_center_usage)

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
    # Individual users do not have premium request paid usage policies
    return false if entity.user?

    return false unless entity.customer

    customer_id = T.must(entity.customer).id.to_s
    billing_client = billing_platform_client
    policy_response = billing_client.get_overage_policy(
      customer_id: customer_id,
      overage_policy_type: "sku",
      name: "copilot_premium_request",
      is_for_business: true
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

  sig { params(this_entity: ::Billing::Types::Account).returns(Integer) }
  def consumed_copilot_licenses_for_entity(this_entity)
    return 0 unless this_entity.is_a?(Business)

    copilot_business = Copilot::Business.new(this_entity)
    return 0 unless copilot_business.copilot_enabled?

    consumed_counts = copilot_business.copilot_enabled_members_count_by_license(consumed_only: true)
    consumed_counts[:business].to_i + consumed_counts[:enterprise].to_i
  rescue => e
    Failbot.report(e)
    0
  end

  private

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def build_budget_prefill
    return {} unless client_feature_flags&.dig(:ipm_budget_deep_linking)

    prefill = {}

    if params[:budget_type].present? && ALLOWED_BUDGET_TYPES.include?(params[:budget_type])
      prefill[:budget_type] = params[:budget_type]
    end

    if params[:budget_scope].present? && ALLOWED_BUDGET_SCOPES.include?(params[:budget_scope])
      prefill[:budget_scope] = params[:budget_scope]
    end

    if params[:target_amount].present? && params[:target_amount].match?(/\A[1-9]\d{0,9}\z/)
      amount = params[:target_amount].to_i
      prefill[:target_amount] = amount if amount > 0
    end

    prefill
  end

  sig { params(this_entity: ::Billing::Types::Account).returns(T::Boolean) }
  def fetch_included_usage_notification_customer(this_entity)
    return false unless this_entity.feature_flag_enabled?(:billing_discount_threshold_notification, default: false)

    customer_id = this_entity.customer&.id.to_s
    return false if customer_id.blank?

    response = billing_platform_client.get_key_value(customer_id: customer_id, key: "included_usage_notification_customer")
    return false if response.is_a?(Billing::Platform::Api::Error)

    response[:value] == "enabled"
  end

  sig { params(entity: ::Billing::Types::Account, pagination: T.nilable(T::Hash[Symbol, T.untyped])).returns(T::Boolean) }
  def paginated_budgets_request?(entity, pagination)
    entity.feature_flag_enabled?(:billing_budget_pagination_enabled, default: false) &&
      pagination.present? &&
      !!(pagination[:page] || pagination[:page_size] || pagination[:scope] || pagination[:exclude_scope] || pagination[:scopes] || pagination[:exclude_scopes])
  end

  sig { params(entity: ::Billing::Types::Account).returns(T::Boolean) }
  def multi_scope_budgets_enabled?(entity)
    return true if entity.is_a?(Business)

    entity.is_a?(Organization) && entity.feature_flag_enabled?(:billing_org_admin_user_level_budgets, default: false)
  end

  sig { returns(Billing::Platform::Api::Client) }
  def billing_platform_client
    Billing::Platform::Api::Client.new
  end
end
