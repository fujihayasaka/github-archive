# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::PrepaidMeteredUsageRefillsController < Stafftools::Businesses::BusinessBaseController
  before_action :enforce_refills_enabled
  before_action :enforce_plan_subscription_synchronized

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Repositories,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  def index
    view = create_view_model(
      Stafftools::PrepaidMeteredUsageRefillsView,
      owner: this_business,
      page: current_page,
    )
    render "stafftools/businesses/prepaid_metered_usage_refills/index", locals: { view: view }
  end

  def destroy
    refill = Billing::PrepaidMeteredUsageRefill.find_by!(id: params[:id], owner: this_business)

    if refill.staff_created?
      refill.destroy
      redirect_to stafftools_prepaid_metered_usage_refills_path(this_business)
    else
      render_404
    end
  end

  private

  def enforce_refills_enabled
    render "stafftools/businesses/prepaid_metered_usage_refills/disabled" unless Billing::PrepaidMeteredUsageRefill.enabled_for?(this_business)
  end

  def enforce_plan_subscription_synchronized
    render "stafftools/businesses/prepaid_metered_usage_refills/not_synchronized" unless this_business&.customer&.sales_serve_plan_subscription.present?
  end
end
