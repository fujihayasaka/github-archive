# typed: strict
# frozen_string_literal: true

class Stafftools::Users::TradeCompliance::ScreeningProfileController < Stafftools::Users::TradeComplianceController

  before_action :ensure_reason_exists
  before_action :ensure_screening_record_exists
  before_action :ensure_valid_screening_status_params, only: :update

  sig { void }
  def update
    success = target_trade_screening_record(ignore_linked_record: true).update(update_screening_status_hash)
    success &&= target.customer&.contacts&.all? { |c| c.update(trade_screening_status: params[:status]) } if target.customer&.contacts&.any?
    if success
      flash[:notice] = "Successfully updated user's trade screening status to '#{target.trade_screening_status}'."
    else
      flash[:error] = "Unable to update screening status for #{target}. Errors: #{target_trade_screening_record.errors.full_messages.to_sentence}"
    end

    redirect_back(fallback_location: stafftools_user_administrative_tasks_path(target))
  end

  sig { void }
  def destroy
    target_trade_screening_record.destroy(actor: actor, reason: params[:reason])
    flash[:notice] = "Trade screening record deleted."

    redirect_back(fallback_location: stafftools_user_administrative_tasks_path(target))
  end

  private

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def update_screening_status_hash
    status_reason = { "status_reason": params[:reason] }
    {
      msft_trade_screening_status: params[:status],
      metadata: target_trade_screening_record.metadata.merge(status_reason),
    }
  end

  sig { void }
  def ensure_valid_screening_status_params
    if params[:status].blank? && AccountScreeningProfile::VALID_SDN_STATUSES.exclude?(params[:status].to_sym)
      flash[:error] = "Please provide a valid status to update user's screening status to."
      redirect_back(fallback_location: stafftools_user_administrative_tasks_path(target))
    end
  end

  sig { void }
  def ensure_reason_exists
    if params[:reason].blank?
      flash[:error] = "You must provide a reason to #{params[:action]} a trade screening record."
      redirect_back(fallback_location: stafftools_user_administrative_tasks_path(target))
    end
  end

  sig { void }
  def ensure_screening_record_exists
    unless target_trade_screening_record.persisted?
      flash[:error] = "There is no existing trade screening record for #{target}."
      redirect_back(fallback_location: stafftools_user_administrative_tasks_path(target))
    end
  end

  # Target user trade screening record for deleting when ToS changes
  sig { params(ignore_linked_record: T::Boolean).returns(AccountScreeningProfile) }
  def target_trade_screening_record(ignore_linked_record: false)
    target.trade_screening_record(ignore_linked_record:)
  end
end
