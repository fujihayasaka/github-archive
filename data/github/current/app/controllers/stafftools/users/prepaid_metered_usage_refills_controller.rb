# typed: true
# frozen_string_literal: true

class Stafftools::Users::PrepaidMeteredUsageRefillsController < StafftoolsController
  layout "layouts/stafftools/organization/billing"

  before_action :require_prepaid_metered_billing
  before_action :enforce_plan_subscription_synchronized

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Repositories,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index], optional: true

  def index
    view = create_view_model(
      Stafftools::PrepaidMeteredUsageRefillsView,
      owner: this_user,
      page: current_page,
    )
    render "stafftools/users/prepaid_metered_usage_refills/index", locals: { view: view }
  end

  def destroy
    refill = ::Billing::PrepaidMeteredUsageRefill.find_by!(id: params[:id], owner: this_user)

    if refill.staff_created?
      refill.destroy
      redirect_to stafftools_user_prepaid_metered_usage_refills_path(this_user)
    else
      render_404
    end
  end

  private

  def require_prepaid_metered_billing
    render_404 unless ::Billing::PrepaidMeteredUsageRefill.enabled_for?(this_user)
  end

  def enforce_plan_subscription_synchronized
    render "stafftools/users/prepaid_metered_usage_refills/not_synchronized" unless this_user.plan_subscription.present?
  end
end
