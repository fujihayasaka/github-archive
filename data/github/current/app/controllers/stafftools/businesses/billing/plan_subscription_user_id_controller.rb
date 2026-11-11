# typed: strict
# frozen_string_literal: true

class Stafftools::Businesses::Billing::PlanSubscriptionUserIdController < Stafftools::Businesses::BusinessBaseController
  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = T.let([
    "Stafftools::Businesses::Billing::PlanSubscriptionUserIdController#destroy",
  ].freeze, T::Array[String])

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    only: [:destroy]

  sig { void }
  def destroy
    plan_subscription = this_business.plan_subscription
    if plan_subscription.nil?
      flash[:error] = "No plan subscription found for this enterprise."
      return redirect_to stafftools_enterprise_billing_path(this_business)
    end

    if plan_subscription.user_id.nil?
      flash[:notice] = "Plan subscription user_id is already blank."
      return redirect_to stafftools_enterprise_billing_path(this_business)
    end

    plan_subscription.update!(user_id: nil)
    flash[:notice] = "Plan subscription user_id has been cleared."
    redirect_to stafftools_enterprise_billing_path(this_business)
  end
end
