# typed: true
# frozen_string_literal: true

class PendingPlanChangesController < ApplicationController

  before_action :login_required, :ensure_user_can_update_pending_plan_change

  def update
    errors = update_pending_plan_change(
      !!params[:cancel_data_packs],
      !!params[:cancel_plan],
      !!params[:cancel_plan_duration],
      !!params[:cancel_seats],
      !!params[:cancel_subscription_item_changes]
    )

    if errors.any?
      flash[:error] = errors.join(", ")
    else
      notice = "Successfully cancelled the pending ".dup
      if params[:cancel_data_packs]
        notice << "LFS pack downgrade."
      elsif params[:cancel_plan_duration]
        notice << "plan duration change."
      else
        notice << "plan change."
      end

      flash[:notice] = notice
    end

    redirect_back(fallback_location: "/")
  end

  private def target_for_conditional_access
    this_user || :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  private

  def this_user # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @this_user ||= User.find_by_login(params[:id])
  end

  def ensure_user_can_update_pending_plan_change
    unless current_user&.site_admin? || this_user.adminable_by?(current_user) || (this_user.organization? && this_user.billing_manager?(current_user))
      render_404
    end
  end

  def update_pending_plan_change(cancel_data_packs, cancel_plan, cancel_plan_duration, cancel_seats, cancel_subscription_item_changes)
    errors = []
    errors << "There are no pending changes to update." unless this_user.pending_cycle_change
    if Billing::PlanTrial.exists?(pending_plan_change: this_user.pending_cycle_change)
      errors << "Changes that revert plans at the end of a trial cannot be modified."
    end
    return errors if errors.any?

    pending_plan_change = this_user.pending_cycle_change
    pending_plan_change.update_attribute(:data_packs, nil) if cancel_data_packs
    pending_plan_change.update_attribute(:plan, nil) if cancel_plan
    pending_plan_change.update_attribute(:plan_duration, nil) if cancel_plan_duration
    pending_plan_change.update_attribute(:seats, nil) if cancel_seats
    if cancel_subscription_item_changes
      pending_plan_change.cancel_pending_subscription_item_changes!
      pending_plan_change.reload
    end
    pending_plan_change.cancel unless pending_plan_change.has_changes?

    []
  end
end
