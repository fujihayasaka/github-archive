# typed: strict
# frozen_string_literal: true

class Stafftools::Businesses::Billing::BillCycleDayController < Stafftools::Businesses::BusinessBaseController

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    only: [:edit]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:edit, :show],
    optional: true

  sig { void }
  def show
    return render_404 unless this_business.eligible_for_self_serve_payment?

    render "stafftools/businesses/billing/bill_cycle_day/show", locals: {
      business: this_business
    }, layout: false
  end

  sig { void }
  def edit
    return render_404 unless this_business.bill_cycle_day_editable_in_stafftools?

    render "stafftools/businesses/billing/bill_cycle_day/edit", locals: {
      business: this_business
    }, layout: false
  end

  sig { void }
  def update
    return render_404 unless this_business.bill_cycle_day_editable_in_stafftools?

    new_bill_cycle_day = params[:bill_cycle_day].to_i
    unless new_bill_cycle_day.between?(1, 31)
      flash[:error] = "Invalid bill cycle day, must be between 1 and 31"
      redirect_to stafftools_enterprise_billing_path(this_business)
      return
    end

    result = ::Billing::UpdateCustomerBillCycleDay.new(this_business, new_bill_cycle_day).call
    if result.success?
      flash[:notice] = "Bill cycle day updated successfully"
    else
      flash[:error] = result.error_message
    end

    redirect_to stafftools_enterprise_billing_path(this_business)
  end
end
