# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::SeatsPlanTypeController < Stafftools::Businesses::BusinessBaseController
  before_action :seats_plan_type_required

  def update
    render_404 unless current_user.feature_enabled?(:site_admin_change_enterprise_seats_plan_type)

    if this_business.can_transition_to_seats_plan_type?(seats_plan_type)
      if this_business.transition_to_seats_plan_type(seats_plan_type)
        flash[:notice] = "Enterprise seats plan type changed to #{seats_plan_type}."
      else
        flash[:error] = this_business.errors.full_messages.join(", ")
      end
    else
      flash[:error] = this_business.reason_unable_to_transition_to_seats_plan_type(seats_plan_type)
    end
    redirect_to :back
  end

  private

  def seats_plan_type_required
    render_404 unless valid_seats_plan_types.include?(seats_plan_type)
  end

  def valid_seats_plan_types
    Business.seats_plan_types.keys.map(&:to_s)
  end

  def seats_plan_type
    params[:seats_plan_type].to_s
  end
end
