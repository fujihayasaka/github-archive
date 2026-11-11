# typed: strict
# frozen_string_literal: true

class Stafftools::Billing::PendingPlanChangesController < StafftoolsController
  before_action :dotcom_required
  before_action :ensure_pending_plan_change_present

  sig { void }
  def destroy
    pending_plan_change.cancel

    if pending_plan_change.errors.present?
      flash[:error] = pending_plan_change.errors.full_messages.join(", ")
    else
      flash[:notice] = "Successfully cancelled the pending plan change."
    end

    redirect_back(fallback_location: "/stafftools")
  end

  private

  sig { void }
  def ensure_pending_plan_change_present
    render_404 unless pending_plan_change.present?
  end

  sig { returns(::Billing::PendingPlanChange) }
  memoize def pending_plan_change
    Billing::PendingPlanChange.find(params[:id])
  end
end
