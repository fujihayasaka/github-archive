# typed: strict
# frozen_string_literal: true

class Businesses::Billing::MarketplaceAppsController < Businesses::BillingsController
  before_action :business_access_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Copilot,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index], optional: true

  DEFAULT_PAGE_SIZE = 10

  sig { void }
  def index
    current_page = params[:page].to_i
    current_page = 1 if current_page == 0
    marketplace_apps = view.organizations_marketplace_apps(page: current_page - 1, page_size: DEFAULT_PAGE_SIZE)

    marketplace_apps_usage = WillPaginate::Collection.create(current_page, DEFAULT_PAGE_SIZE, marketplace_apps[:total_apps_count]) do |pager|
      pager.replace(marketplace_apps[:apps])
    end
    hide_pagination = marketplace_apps[:total_apps_count] <= DEFAULT_PAGE_SIZE

    render "businesses/billing_platform/marketplace_apps", locals: {
      view: view,
      marketplace_apps_usage: marketplace_apps_usage,
      hide_pagination: hide_pagination
    }
  end

  private

  sig { returns(Businesses::BillingSettings::ProductUsageView) }
  memoize def view
    Businesses::BillingSettings::ProductUsageView.new(current_user: current_user, business: this_business)
  end
end
