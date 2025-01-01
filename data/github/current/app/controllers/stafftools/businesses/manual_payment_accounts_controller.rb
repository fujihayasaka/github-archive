# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::ManualPaymentAccountsController < Stafftools::Businesses::BusinessBaseController

  skip_before_action :business_required, only: %i(index)

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: %i(index)

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index], optional: true

  def index
    render "stafftools/businesses/manual_payment_enterprise_accounts_list", layout: "stafftools", locals: {
      businesses: businesses.paginate(page: current_page, per_page: DEFAULT_PAGE_SIZE),
      filter: filter,
      query: params[:query],
    }
  end

  def update
    case params[:operation].to_s
    when "upgrade"
      this_business.upgrade_to_business_plus_plan
      flash[:notice] = "Upgraded #{this_business.name} to the enterprise plan."
    when "downgrade"
      this_business.downgrade_to_free_plan
      flash[:notice] = "Downgraded #{this_business.name} to the free plan."
    else
      raise RuntimeError, %Q[Unsupported operation param provided: "#{params[:operation]}"]
    end
    redirect_to manual_payment_accounts_stafftools_enterprises_path
  end

  private

  def manual_payment_params
    params.permit(:query, :active_page, :page, :tab, :format,
      filter: [])
  end

  memoize def businesses
    Business.auto_pay_rbi_disabled.for_query(params[:query])
  end

  memoize def filter
    manual_payment_params[:filter].to_h.presence || HashWithIndifferentAccess.new
  end
end
