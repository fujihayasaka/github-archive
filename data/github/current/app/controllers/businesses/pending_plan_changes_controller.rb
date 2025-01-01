# typed: true
# frozen_string_literal: true

class Businesses::PendingPlanChangesController < Businesses::BusinessController
  include VerifiedFetchDependency

  before_action :ensure_user_can_update_pending_plan_change

  allow_verified_fetch only: [:update]

  def update
    errors = update_pending_plan_change(
      params[:cancel_plan_duration].present?,
      params[:cancel_seats].present?
    )

    if errors.any?
      handle_error(errors.join(", "))
    else
      notice = "Successfully cancelled the pending ".dup
      if params[:cancel_seats]
        notice << "licenses change."
      elsif params[:cancel_plan_duration]
        notice << "plan duration change."
      else
        notice << "plan change."
      end

      handle_success(notice)
    end
  end

  private

  def handle_error(error_message)
    respond_to do |format|
      format.html do
        flash[:error] = error_message
        redirect_back(fallback_location: "/")
      end
      format.json { render json: { error: error_message }, status: :unprocessable_entity }
    end
  end

  def handle_success(success_message)
    respond_to do |format|
      format.html do
        flash[:notice] = success_message
        redirect_back(fallback_location: "/")
      end
      format.json { render json: { success: success_message }, status: :ok }
    end
  end

  def ensure_user_can_update_pending_plan_change
    feature_flag_enabled = GitHub.flipper[:billing_cancel_pending_plan_changes_via_stafftools].enabled?
    staff_and_feature_enabled = current_user.site_admin? && feature_flag_enabled

    unless staff_and_feature_enabled || this_business.adminable_by?(current_user) || this_business.billing_manager?(current_user)
      render_404
    end
  end

  def update_pending_plan_change(cancel_plan_duration, cancel_seats)
    errors = []
    errors << "There are no pending changes to update." unless this_business.pending_cycle_change
    return errors if errors.any?

    pending_plan_change = this_business.pending_cycle_change
    pending_plan_change.update_attribute(:plan_duration, nil) if cancel_plan_duration
    pending_plan_change.update_attribute(:seats, nil) if cancel_seats
    pending_plan_change.cancel unless pending_plan_change.has_changes?
    []
  end
end
