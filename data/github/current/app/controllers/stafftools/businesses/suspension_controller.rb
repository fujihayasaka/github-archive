# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::SuspensionController < Stafftools::Businesses::BusinessBaseController

  def create
    if this_business.suspend(params[:reason], actor: current_user, send_email: true)
      flash[:notice] = "Suspended #{this_business.name}."
    else
      flash[:error] = "Failed to suspend the enterprise. #{this_business.errors.full_messages.to_sentence}"
    end
    redirect_to :back
  end

  def destroy
    if this_business.unsuspend(params[:reason], actor: current_user)
      flash[:notice] = "Unsuspended #{this_business.name}."
    else
      flash[:error] = "Failed to unsuspend the enterprise. #{this_business.errors.full_messages.to_sentence}"
    end
    redirect_to :back
  end
end
