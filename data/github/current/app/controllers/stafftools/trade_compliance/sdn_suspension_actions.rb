# typed: strict
# frozen_string_literal: true

module Stafftools::TradeCompliance::SdnSuspensionActions
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { StafftoolsController }

  included do
    sig { void }
    def create
      if params[:reason].present?
        sdn_target.sdn_suspend(staff_user: current_user, reason: params[:reason])
      end

      set_flash_notice

      redirect_back(fallback_location: fallback_location)
    end

    sig { void }
    def destroy
      if params[:reason].present?
        sdn_target.sdn_unsuspend(staff_user: current_user, reason: params[:reason])
      end

      set_flash_notice(prefix: "un")

      redirect_back(fallback_location: fallback_location)
    end
  end

  private

  sig { overridable.returns(Billing::Types::Account) }
  def sdn_target
    this_user
  end

  sig { params(prefix: String).void }
  def set_flash_notice(prefix: "")
    if params[:reason].blank?
      flash[:error] = "Reason for #{prefix}suspension is required."
    elsif sdn_target.errors.any?
      flash[:error] = "An error was encountered while attempting to perform SDN #{prefix}suspension: #{sdn_target.errors.full_messages.to_sentence}."
    else
      flash[:notice] = "Successfully #{prefix}suspended for #{sdn_target}"
    end
  end

  sig { returns(String) }
  def fallback_location
    if sdn_target.business?
      return stafftools_enterprise_trade_compliance_path(sdn_target)
    end
    stafftools_user_administrative_tasks_path(sdn_target)
  end
end
