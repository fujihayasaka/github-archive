# typed: strict
# frozen_string_literal: true

class Stafftools::Users::TradeCompliance::SdnSuspensionController < Stafftools::Users::TradeComplianceController
  extend T::Sig

  sig { void }
  def create
    if params[:reason].present?
      target.sdn_suspend(staff_user: actor, reason: params[:reason])
    end

    set_flash_notice

    redirect_back(fallback_location: stafftools_user_administrative_tasks_path(target))
  end

  sig { void }
  def destroy
    if params[:reason].present?
      target.sdn_unsuspend(staff_user: actor, reason: params[:reason])
    end

    set_flash_notice(prefix: "un")

    redirect_back(fallback_location: stafftools_user_administrative_tasks_path(target))
  end

  private

  sig { params(prefix: String).void }
  def set_flash_notice(prefix: "")
    if params[:reason].blank?
      flash[:error] = "Reason for #{prefix}suspension is required."
    elsif target.errors.any?
      flash[:error] = "An error was encountered while attempting to perform SDN #{prefix}suspension: #{target.errors.full_messages.to_sentence}."
    else
      flash[:notice] = "Successfully #{prefix}suspended for #{target}"
    end
  end
end
