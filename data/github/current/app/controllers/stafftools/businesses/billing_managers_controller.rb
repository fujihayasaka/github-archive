# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::BillingManagersController < Stafftools::Businesses::BusinessBaseController
  before_action :check_for_owners, only: %w(index)

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Configurations,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index], optional: true

  def index
    billing_managers = this_business.admins(query: params[:query], role: :billing_manager)
      .paginate(page: current_page, per_page: DEFAULT_PAGE_SIZE)
    render "stafftools/businesses/billing_managers/index", locals: { billing_managers: billing_managers }
  end

  def destroy
    billing_manager = ::User.find_by login: params[:id]

    unless billing_manager
      flash[:error] = "User #{params[:id]} does not exist."
      return redirect_to stafftools_enterprise_billing_managers_path(this_business)
    end

    this_business.billing.remove_manager(billing_manager, actor: current_user)
    flash[:notice] = "Removed billing manager #{billing_manager.login}."
    redirect_to stafftools_enterprise_billing_managers_path(this_business)
  end
end
