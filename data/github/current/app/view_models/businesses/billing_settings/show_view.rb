# typed: true
# frozen_string_literal: true

class Businesses::BillingSettings::ShowView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  extend T::Sig

  include UrlHelpers
  include Businesses::AzureSubscriptions
  include GitHub::Memoizer

  delegate :organizations, :sales_serve_plan_subscription, to: :business

  sig { returns(Business) }
  attr_reader :business

  sig { returns(T::Array[AssetStatusUsage]) }
  def organizations_asset_statuses
    @_organizations_asset_statuses ||= T.let(organizations.each_with_object([]) do |organization, statuses|
      asset_status = organization.asset_status || organization.build_asset_status
      next if asset_status.bandwidth_usage.zero? && asset_status.storage_usage.zero?

      statuses << AssetStatusUsage.new(
        organization,
        asset_status: asset_status,
      )
    end, T.nilable(T::Array[AssetStatusUsage]))

    @_sorted_organizations_asset_statuses ||= T.let(
      sort_by_admin_access_and_org_name(@_organizations_asset_statuses),
      T.nilable(T::Array[AssetStatusUsage])
    )
  end

  sig { returns(T::Boolean) }
  def has_azure_token?
    client = Billing::Azure::BusinessSubscriptionClient.new(current_user, business)
    client.has_token?
  end

  sig { returns(Integer) }
  def number_of_organizations_without_asset_usage
    @_number_of_organizations_without_asset_usage ||= T.let(
      organizations.count - organizations_asset_statuses.count,
      T.nilable(Integer)
    )
  end

  sig { returns(T::Array[::Billing::Zuora::Invoice]) }
  def invoices
    @_invoices ||= T.let(Billing::Zuora::Invoice.invoices_for_account(business.customer&.zuora_account_id.to_s)
      .select(&:posted?)
      .reject(&:suppress_from_customer_view?)
      .sort_by(&:invoice_date)
      .reverse, T.nilable(T::Array[::Billing::Zuora::Invoice]))
  rescue Zuorest::HttpError, Faraday::Error => e
    Failbot.report!(e, app: "github-zuora")
    @_invoices = []
  end

  sig { returns(T.nilable(::Billing::Zuora::Invoice)) }
  def invoice
    @_invoice ||= T.let(invoices.first, T.nilable(::Billing::Zuora::Invoice))
  end

  sig { returns(T::Boolean) }
  def show_depleted_prepaid_credits_banner?
    has_past_prepaid_credits? && !prepaid_credit_balance.positive?
  end

  sig { returns(Integer) }
  def package_registry_included_bandwidth
    business.plan.package_registry_included_bandwidth
  end

  sig { returns(T.nilable(String)) }
  def linked_azure_subscription
    business.customer&.azure_subscription_id
  end

  sig { returns(String) }
  def linked_azure_subscription_name
    business.customer&.azure_subscription_name.presence || "Subscription"
  end

  sig { returns(Float) }
  def shared_storage_included_gigabytes
    to_gigabytes(business.plan.shared_storage_included_megabytes)
  end


  sig { params(explicit_tenant_selected: T::Boolean, tenant: String).returns(URI) }
  def azure_subscription_uri(explicit_tenant_selected: false, tenant: "common")
    uri = URI("https://login.microsoftonline.com/#{tenant}/oauth2/v2.0/authorize")
    state_hash = {
      business_slug: business.slug,
      explicit_tenant_selected: explicit_tenant_selected
    }

    if GitHub.multi_tenant_enterprise?
      # We pass the host name with tenant so the Azure redirects will work in Proxima where customers have custom subdomains
      state_hash[:host_name] = GitHub.host_name_with_tenant
    end


    state_encoded = hash_to_state(hash: state_hash)

    uri.query = URI.encode_www_form({
      client_id: GitHub.azure_oauth_app_id,
      redirect_uri: GitHub.azure_oauth_app_redirect_uri_for_businesses,
      scope: "https://management.azure.com/user_impersonation",
      response_type: "code",
      state: state_encoded,
      response_mode: "query",
      prompt: "select_account"
    })
    uri
  end

  sig { returns(Symbol) }
  def azure_subscription_removal_scheme
    if prevent_azure_subscription_removal?
      :danger
    else
      :warning
    end
  end

  sig { returns(String) }
  def azure_subscription_removal_message
    if prevent_azure_subscription_removal?
      "You cannot remove your Azure subscription as this is your main form of payment."
    else
      "Removing the Azure subscription from this account will cause all metered services to be billed directly through GitHub."
    end
  end

  sig { returns(T::Boolean) }
  memoize def prevent_azure_subscription_removal?
    business.billed_through_azure_subscription? && !business.customer&.valid_zuora_with_payment?
  end

  sig { returns(T::Array[T::Hash[Symbol, String]]) }
  def navigation_tabs
    @_tabs ||= T.let(
      begin
        tabs = T.let([{ name: "Usage", path: settings_billing_enterprise_path(business) }], T::Array[T::Hash[Symbol, String]])
        tabs << { name: "Marketplace apps", path: settings_billing_tab_enterprise_path(business, :marketplace_apps) } if show_marketplace_apps_tab?
        tabs << { name: "Spending limit", path: settings_billing_tab_enterprise_path(business, :spending_limit) } if show_spending_limits_tab?
        tabs << { name: "Billing emails", path: settings_billing_tab_enterprise_path(business, :billing_emails) } if show_legacy_billing_emails_tab?
        tabs << { name: "Budgets", path: settings_billing_tab_enterprise_path(business, :budgets) } if show_budgets_tab?
        tabs << { name: "Payment information", path: settings_billing_tab_enterprise_path(business, :payment_information) } if show_payment_information_tab?
        tabs << { name: "Past invoices", path: settings_billing_tab_enterprise_path(business, :past_invoices) } if show_past_invoices_tab?
        tabs << { name: "Sponsorships", path: settings_billing_tab_enterprise_path(business, :sponsorships) } if show_sponsorships_tab?
        tabs
      end, T.nilable(T::Array[T::Hash[Symbol, String]])
    )
  end

  sig { returns(::Billing::Budget) }
  def actions_and_packages_budget
    @_actions_and_packages_budget ||= T.let(business.budget_for(group: :shared), T.nilable(::Billing::Budget))
  end

  sig { returns(T::Boolean) }
  def has_shared_budget?
    actions_and_packages_budget.enforcement_configured?
  end

  sig { returns(::Billing::Budget) }
  def codespaces_budget
    @_codespaces_budget ||= T.let(business.budget_for(group: :codespaces), T.nilable(::Billing::Budget))
  end

  sig { returns(T::Boolean) }
  def has_codespaces_budget?
    codespaces_budget.enforcement_configured?
  end

  sig { returns(T::Boolean) }
  def show_alert_for_missing_azure_id?
    business.billed_through_azure_subscription? && !business.linked_azure_subscription?
  end

  sig { returns(T::Boolean) }
  def show_invoice_overview?
    business.pays_github_directly? && !business.reseller_customer? && business.invoiced? && invoice.present?
  end
  alias_method :show_past_invoices_tab?, :show_invoice_overview?

  sig { returns(::Billing::Public::Budgets::Permission) }
  def business_budget_permission
    @_business_budget_permission ||= T.let(Billing::Public::Budgets::Permission.new(business, current_user), T.nilable(::Billing::Public::Budgets::Permission))
  end

  sig { returns(T::Boolean) }
  def show_budgets_tab?
    business_budget_permission.show_org_level_budgets_tab?
  end

  sig { returns(T::Boolean) }
  def show_spending_limits_tab?
    business_budget_permission.show_enterprise_spending_limit_tab? && !copilot_standalone?
  end

  sig { returns(T::Boolean) }
  def show_legacy_billing_emails_tab?
    !business.billed_via_billing_platform?
  end

  sig { returns(T::Boolean) }
  def show_migration_banner?
    return false unless business.vnext_planned_migration_date
    ((business.vnext_planned_migration_date.utc - 30.days)..business.vnext_planned_migration_date.utc).include?(DateTime.now.utc) &&
      business.feature_enabled?(:billing_vnext_migration_banner)
  end


  sig { returns(T::Boolean) }
  def display_cost_center_message?
    business.billed_via_billing_platform?
  end

  sig { returns(T::Boolean) }
  def show_marketplace_apps_tab?
    business_budget_permission.show_marketplace_apps_tab? && !business.billed_via_billing_platform?
  end

  sig { returns(T::Boolean) }
  def show_sponsorships_tab?
    business_budget_permission.show_sponsorships_tab? && !business.billed_via_billing_platform?
  end

  sig { returns(T::Array[::Billing::SubscriptionItem]) }
  memoize def self_serve_marketplace_subscription_items
    return [] unless business.self_serve_payment?

    subscription = T.cast(business.get_plan_subscription_or_null_plan, ::Billing::PlanSubscription)
    subscription.active_marketplace_listing_subscription_items.to_a
  end

  sig { params(page: Integer, page_size: Integer).returns(T::Hash[Symbol, T.untyped]) }
  def organizations_marketplace_apps(page:, page_size: 10)
    items = self_serve_marketplace_subscription_items
    total_apps_count = items.count

    apps = T.must(items[page * page_size, page_size]).group_by { |i| i.subscribable.listing }.map do |listing, items|
      {
        listing: listing,
        items: items
      }
    end

    {
      apps: apps,
      total_apps_count: total_apps_count
    }
  end

  sig { returns(T::Hash[Organization, T::Array[Billing::SubscriptionItem]]) }
  memoize def organizations_sponsorships
    business.active_organizations_sponsorships
  end

  sig { returns(String) }
  def manage_spending_limit_href
    if show_budgets_tab?
      settings_billing_tab_enterprise_path(business, :budgets)
    else
      settings_billing_tab_enterprise_path(business, :spending_limit)
    end
  end

  sig { returns(T::Boolean) }
  def show_payment_information_tab?
    !business.billed_via_billing_platform?
  end

  sig { returns(T::Boolean) }
  def has_past_prepaid_credits?
    Billing::PrepaidMeteredUsageRefill.where(owner: business).exists?
  end

  sig { returns(Billing::Money) }
  memoize def prepaid_credit_balance
    business.customer&.credit_balance || Billing::Money.new(0)
  end

  sig { returns(::Billing::Budget) }
  def enterprise_shared_budget
    # returns an existing budget if one exists
    business.budget_for(group: :shared, budget_name: "#{business.name} - Default Budget")
  end

  sig { returns(::Billing::Budget) }
  def enterprise_codespaces_budget
    # returns an existing budget if one exists
    business.budget_for(group: :codespaces, budget_name: "#{business.name} - Default Budget")
  end

  sig { returns(T::Array[Billing::Budget]) }
  def organization_budgets
    business.organizations.flat_map { |org| Billing::Budget.where(owner: org) }
  end

  sig { returns(T::Boolean) }
  def has_persisted_budget?
    # only show the manage budgets banner when the user hasn't created any budgets yet
    organization_budgets.any? || enterprise_codespaces_budget.persisted? || enterprise_shared_budget.persisted?
  end

  sig { params(budget: ::Billing::Budget).returns(Integer) }
  def budget_progress_percentage(budget)
    usage_checker.budget_percentage_used(budget)
  end

  sig { params(budget: ::Billing::Budget).returns(BigDecimal) }
  def budget_amount_spent(budget)
    Billing::Money.new(usage_checker.total_spent_towards_budget(budget)).dollars
  end

  sig { params(budget: ::Billing::Budget).returns(String) }
  def show_budget_limit(budget)
    budget.enforce_spending_limit ? "#{Billing::Money.new(budget.spending_limit_in_subunits).format} limit" : "Unlimited"
  end

  sig { returns(String) }
  def default_budget_limit
    enterprise_shared_budget.enforce_spending_limit ? "a limit of $0" : "unlimited"
  end

  sig { params(budget: ::Billing::Budget).returns(T::Boolean) }
  def is_business_budget?(budget)
    budget.owner.is_a?(Business)
  end

  sig { params(budget_product: Symbol).returns(String) }
  def product_label(budget_product)
    Billing::Budget.product_labels[budget_product] || "Undefined"
  end

  sig { returns(T::Array[Billing::Budget]) }
  def all_budgets
    # only show the manage budgets banner when the user hasn't created any budgets yet
    [enterprise_codespaces_budget, enterprise_shared_budget] + organization_budgets
  end

  sig { returns(T::Boolean) }
  def has_education_bundle?
    !!sales_serve_plan_subscription&.education_bundle?
  end

  sig { returns(String) }
  def education_bundle_text
    "GitHub Education #{sales_serve_plan_subscription.education_bundle.humanize}"
  end

  sig { returns(T::Boolean) }
  def spending_limit_enabled?
    Billing::Budget.configurable?(business)
  end

  sig { returns(String) }
  def spending_limit_path
    manage_spending_limit_href
  end

  sig { returns(T::Boolean) }
  def show_shared_codespace_usage_component
    business.feature_enabled?(:shared_codespace_usage_component)
  end

  sig { returns(T::Boolean) }
  def show_ghas_usage_for_user_repos?
    AdvancedSecurity::Features::Business::AdvancedSecurity.new(business).feature_available_for_user_repositories?
  end

  sig { returns(T::Array[String]) }
  def copilot_headers
    if copilot_standalone?
      ["Seat usage", "Spending"]
    else
      ["Organization", "Seat usage", "Spending"]
    end
  end

  sig { returns(T::Boolean) }
  def copilot_standalone?
    Copilot::Business.new(business).copilot_standalone?
  end

  private

  sig { returns(Billing::UsageChecker) }
  memoize def usage_checker
    Billing::UsageChecker.new(account: business, product_names: %w[actions packages shared_storage codespaces], timeout: 5)
  end

  sig { params(megabytes: ::Billing::Types::NonMoneyNumeric).returns(Float) }
  def to_gigabytes(megabytes)
    (megabytes.megabytes / 1.gigabyte.to_f).round(2)
  end

  # Sort based on adminable_by current user and organization name
  def sort_by_admin_access_and_org_name(orgs_usage)
    orgs_usage.sort_by { |usage| [usage.organization.adminable_by?(current_user) ? 0 : 1, usage.organization.name] }
  end
end
