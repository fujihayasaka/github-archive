# typed: true
# frozen_string_literal: true

class Businesses::BillingSettings::MarketplaceAppsController < Businesses::BusinessController
  before_action :ensure_billing_enabled
  before_action :business_access_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show], optional: true

  DEFAULT_PAGE_SIZE = 10

  def show
    current_page = params[:page].to_i
    current_page = 1 if current_page == 0
    marketplace_apps = view.organizations_marketplace_apps(page: current_page - 1, page_size: DEFAULT_PAGE_SIZE)

    marketplace_apps_usage = WillPaginate::Collection.create(current_page, DEFAULT_PAGE_SIZE, marketplace_apps[:total_apps_count]) do |pager|
      pager.replace(marketplace_apps[:apps])
    end
    hide_pagination = marketplace_apps[:total_apps_count] <= DEFAULT_PAGE_SIZE

    render partial: "businesses/billing_settings/marketplace_apps", locals: {
      view: view,
      marketplace_apps_usage: marketplace_apps_usage,
      hide_pagination: hide_pagination
    }
  end

  private

  memoize def view
    Businesses::BillingSettings::ProductUsageView.new(current_user: current_user, business: this_business)
  end
end
