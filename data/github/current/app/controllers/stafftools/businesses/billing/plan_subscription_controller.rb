# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::Billing::PlanSubscriptionController < Stafftools::Businesses::BusinessBaseController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    only: [:edit]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    only: [:show]

  def show
    render "stafftools/businesses/billing/plan_subscription/show", locals: {
      business: this_business
    }, layout: false
  end

  def edit
    render "stafftools/businesses/billing/plan_subscription/edit", locals: {
      business: this_business
    }, layout: false
  end

  def update
    result = Billing::SchedulePlanChange.run \
      account: this_business,
      actor: current_user,
      seats: this_business.seats,
      plan_duration: params[:plan_duration]
    redirect_to stafftools_enterprise_billing_path(this_business)
  end
end
