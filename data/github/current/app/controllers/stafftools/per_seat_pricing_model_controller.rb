# typed: true
# frozen_string_literal: true
class Stafftools::PerSeatPricingModelController < StafftoolsController
  include SeatsHelper
  before_action :ensure_user_exists
  before_action :ensure_billing_enabled

  layout "layouts/stafftools/organization/billing"

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show], optional: true

  def show
    load_per_seat_pricing_model
    if this_user.plan.per_seat?
      redirect_to billing_stafftools_user_path(this_user)
      return
    end

    respond_to do |format|
      format.json do
        render json: hash_for_pricing_model_change(@per_seat_pricing_model, stafftools_user_per_seat_pricing_model_path(this_user))
      end

      format.html do
        render "stafftools/per_seat_pricing_model/show"
      end
    end
  end

  def update
    load_per_seat_pricing_model

    if @per_seat_pricing_model.switch(actor: current_user)
      flash[:notice] = "Pricing model changed to per seat"
    else
      flash[:error] = @per_seat_pricing_model.error_messages.join
    end

    redirect_to :back
  end

  private

  def load_per_seat_pricing_model # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @per_seat_pricing_model ||=
      ::Billing::PlanChange::PerSeatPricingModel.new(this_user, seats: seats, plan_duration: plan_duration)
  end

  def plan_duration
    params.fetch(:duration, this_user.plan_duration)
  end

  def seats
    params.fetch(:seats, this_user.default_seats)
  end
end
