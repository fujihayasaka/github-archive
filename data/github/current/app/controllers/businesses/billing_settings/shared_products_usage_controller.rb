# typed: true
# frozen_string_literal: true

class Businesses::BillingSettings::SharedProductsUsageController < Businesses::BusinessController
  before_action :ensure_billing_enabled
  before_action :business_access_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    only: [:show_actions]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    only: [:show_packages]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    only: [:show_shared_storage]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    only: [:show_shared_storage_overview]

  DEFAULT_PAGE_SIZE = 10

  def show_actions # rubocop:todo GitHub/UseRestfulActions
    render partial: "businesses/billing_settings/actions_usage", locals: { view: view }
  end

  def show_packages # rubocop:todo GitHub/UseRestfulActions
    render partial: "businesses/billing_settings/packages_usage", locals: { view: view }
  end

  def show_shared_storage_overview # rubocop:todo GitHub/UseRestfulActions
    render partial: "businesses/billing_settings/shared_storage_overview", locals: { view: view }
  end

  def show_shared_storage # rubocop:todo GitHub/UseRestfulActions
    pagination_enabled = GitHub.flipper[:shared_storage_pagination].enabled?(this_business)

    if pagination_enabled
      current_page = params[:page].to_i
      current_page = 1 if current_page == 0

      orgs_and_counts = view.get_organizations_storage_usage(page: current_page - 1, page_size: DEFAULT_PAGE_SIZE)

      organizations_storage_usage = WillPaginate::Collection.create(current_page, DEFAULT_PAGE_SIZE, orgs_and_counts[:total_orgs_count]) do |pager|
        pager.replace(orgs_and_counts[:orgs])
      end

      hide_pagination = orgs_and_counts[:total_orgs_count] <= DEFAULT_PAGE_SIZE
    else
      organizations_storage_usage = view.organizations_storage_usage
      hide_pagination = true
    end

    render partial: "businesses/billing_settings/shared_storage", locals: {
      view: view,
      organizations_storage_usage: organizations_storage_usage,
      pagination_enabled: pagination_enabled,
      hide_pagination: hide_pagination
    }
  end

  # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
  def view # rubocop:todo GitHub/UseRestfulActions # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @view ||= Businesses::BillingSettings::ProductUsageView.new(current_user: current_user, business: this_business)
  end
  # rubocop:enable GitHub/ControllersShouldUseMemoizeForMemoization
end
