# typed: true
# frozen_string_literal: true

class Businesses::BillingSettings::ProductUsageView < Businesses::BillingSettings::ShowView
  def organizations_actions_usage
    @_organizations_actions_usage ||= organizations.each_with_object([]) do |organization, usages|
      usage = Billing::ActionsUsage.account_usage(organization, shared_usage: accounts_shared_products_usage(products: ["actions"]))
      next if usage.has_error? || usage.total_standard_runners_minutes_used.zero?

      usages << ActionsUsage.new(
        organization,
        usage: usage,
      )
    end
    @_sorted_organizations_actions_usage ||= sort_by_admin_access_and_org_name(@_organizations_actions_usage)
  end

  def number_of_organizations_without_actions_usage
    @_number_of_organizations_without_actions_usage ||= organizations.count - organizations_actions_usage.count
  end

  def organizations_packages_usage
    @_organizations_packages_usage ||= organizations.each_with_object([]) do |organization, usages|
      usage = Billing::PackageRegistryUsage.account_usage(organization, shared_usage: accounts_shared_products_usage(products: ["packages"]))
      next if usage.has_error?
      next if usage.private_gigabytes_used.zero?

      usages << PackageUsage.new(organization, usage: usage)
    end

    @_sorted_organizations_packages_usage ||= sort_by_admin_access_and_org_name(@_organizations_packages_usage)
  end

  def number_of_organizations_without_packages_usage
    @_number_of_organizations_without_packages_usage ||= organizations.count - organizations_packages_usage.count
  end

  def get_organizations_storage_usage(page:, page_size: 10)
    total_orgs_count = organizations.count

    current_page_orgs = organizations[page * page_size, page_size].each_with_object([]) do |organization, usages|
      usage = Billing::SharedStorageUsage.account_usage(organization, shared_usage: accounts_shared_products_usage(products: ["shared_storage"]))
      next if usage.has_error?
      # Display orgs with zero usage (not skipping if org has zero usage)

      usages << SharedStorageUsage.new(organization, usage: usage)
    end

    {
      orgs: current_page_orgs,
      total_orgs_count: total_orgs_count
    }
  end

  def organizations_storage_usage
    @_organizations_storage_usage ||= organizations.each_with_object([]) do |organization, usages|
      usage = Billing::SharedStorageUsage.account_usage(organization, shared_usage: accounts_shared_products_usage(products: ["shared_storage"]))
      next if usage.has_error?
      next if usage.estimated_monthly_private_megabytes.zero?

      usages << SharedStorageUsage.new(organization, usage: usage)
    end

    @_sorted_organizations_storage_usage ||= sort_by_admin_access_and_org_name(@_organizations_storage_usage)
  end

  def number_of_organizations_without_storage_usage
    @_number_of_organizations_without_storage_usage ||= organizations.count - organizations_storage_usage.count
  end

  def shared_storage_usage_has_error?
    shared_storage.has_error?
  end

  def shared_storage_estimated_monthly_private_gigabytes
    to_gigabytes(shared_storage.estimated_monthly_private_megabytes)
  end

  def billing_api_client_wrapper
    @_billing_api_client_wrapper ||= Billing::Api::ClientWrapper.new(billable_owner: business)
  end

  def codespaces_monthly_usage
    @_codespaces_monthly_usage ||= billing_api_client_wrapper.codespaces_monthly_usage
  end

  def copilot_monthly_usage
    @_copilot_monthly_usage ||= billing_api_client_wrapper.copilot_monthly_usage
  end

  def usage_threshold_banners
    @usage_threshold_banners ||= Billing::Budget.products.values.map do |budget_group|
      Billing::UsageThresholdBanner.new(owner: business, actor: current_user, budget_group: budget_group.to_sym)
    end
  end

  private

  def shared_storage
    @_shared_storage ||= Billing::SharedStorageUsage.account_usage(business, shared_usage: accounts_shared_products_usage)
  end

  def accounts_shared_products_usage(products: %w[actions packages shared_storage])
    products_key = products.join("_")
    @accounts_shared_products_usage ||= {}
    @accounts_shared_products_usage[products_key] ||= GitHub.dogstats.time("accounts_shared_products_usage.time") do
      Billing::BaseUsage.shared_accounts_usage(
        business,
        products: products,
      )
    end
  end
end
