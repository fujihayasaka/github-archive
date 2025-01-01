# typed: strict
# frozen_string_literal: true

class Stafftools::Businesses::TradeCompliance::ScreeningStatusController < Stafftools::Businesses::TradeComplianceController

  sig { void }
  def update
    if valid_screening_status_params?
      success = this_business.trade_screening_record.update(update_screening_status_hash)

      if success
        flash[:notice] = "Successfully updated business's trade screening status to '#{this_business.trade_screening_record.msft_trade_screening_status}'."
      else
        flash[:error] = "Unable to update screening status for #{this_business}. Errors: #{this_business.trade_screening_record.errors.full_messages.to_sentence}"
      end
    else
      flash[:error] = "Please provide a valid status and reason to update this business's screening status to."
    end

    redirect_back(fallback_location: stafftools_enterprise_trade_compliance_path(this_business))
  end

  private

  sig { returns(T::Boolean) }
  def valid_screening_status_params?
    return false unless params[:status].present?
    return false unless params[:reason].present?
    AccountScreeningProfile::VALID_SDN_STATUSES.include?(params[:status].to_sym)
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def update_screening_status_hash
    status_reason = { "status_reason": params[:reason] }
    {
      msft_trade_screening_status: params[:status],
      metadata: this_business.trade_screening_record.metadata.merge(status_reason),
    }
  end
end
