# typed: strict
# frozen_string_literal: true


class Stafftools::Users::TradeCompliance::RestrictionsEnforcementController < Stafftools::Users::TradeComplianceController

  before_action :ensure_reason_exists
  before_action :ensure_restrictions_exists, only: [:update, :destroy]

  sig { void }
  def create
    if target.has_any_trade_restrictions?
      flash[:error] = "This account has already been trade controls restricted"
      return redirect_back(fallback_location: stafftools_user_administrative_tasks_path(target))
    end

    update_restriction(restriction_type: params[:restriction_type], action_message: "enforced")
    redirect_back(fallback_location: stafftools_user_administrative_tasks_path(target))
  end

  sig { void }
  def update
    update_restriction(restriction_type: params[:restriction_type], action_message: "updated")
    redirect_back(fallback_location: stafftools_user_administrative_tasks_path(target))
  end

  sig { void }
  def destroy
    update_restriction(restriction_type: "override", action_message: "removed")
    redirect_back(fallback_location: stafftools_user_administrative_tasks_path(target))
  end

  private

  sig { returns(TradeControls::Compliance::ComplianceType) }
  memoize def compliance
    TradeControls::Compliance.for(actor: actor, reason: params[:reason])
  end

  sig { params(restriction_type: String, action_message: String).returns(T::Boolean) }
  def update_restriction(restriction_type:, action_message:)
    event = target.trade_controls_restriction.restriction_event(restriction_type)

    if event.blank? || target.trade_controls_restriction.valid_events_with_subsequent_state.flatten.exclude?(event)
      flash[:error] = "#{restriction_type} is not a valid restriction type"
      return false
    end

    if target.trade_controls_restriction.public_send("#{event}!".to_sym, compliance: compliance) # rubocop:disable GitHub/AvoidObjectSendWithDynamicMethod
      flash[:notice] = "Successfully #{action_message} trade controls restrictions for #{target}"
      return true
    end

    flash[:notice] = "Failed to #{action_message} trade controls restrictions for #{target}"
    false
  end

  sig { void }
  def ensure_reason_exists
    return unless params[:reason].blank?

    flash[:error] = "You must provide a reason to modify trade controls restrictions."
    redirect_back(fallback_location: stafftools_user_administrative_tasks_path(target))
  end

  sig { void }
  def ensure_restrictions_exists
    return if target.has_any_trade_restrictions?

    flash[:error] = "This account is not trade controls restricted."
    redirect_back(fallback_location: stafftools_user_administrative_tasks_path(target))
  end
end
