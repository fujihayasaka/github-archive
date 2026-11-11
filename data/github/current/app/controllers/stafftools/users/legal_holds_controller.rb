# typed: true
# frozen_string_literal: true

class Stafftools::Users::LegalHoldsController < StafftoolsController
  def create
    if target_user.place_legal_hold(actor: current_user)
      flash[:notice] = "Successfully placed a legal hold on #{target_user}."
    else
      flash[:error] = "Couldn't place a legal hold on #{target_user}."
    end

    redirect_to redirect_destination
  end

  def destroy
    if target_user.clear_legal_hold(actor: current_user)
      flash[:notice] = "Successfully cleared a legal hold on #{target_user}."
    else
      flash[:error] = "Couldn't remove a legal hold on #{target_user}."
    end

    redirect_to redirect_destination
  end

  private

  def target_user # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @_target_user ||= if params[:deleted_user_id]
      User.new(id: params[:deleted_user_id], login: params[:login])
    else
      ensure_user_exists
      this_user
    end
  end

  def redirect_destination
    if target_user.persisted?
      stafftools_user_administrative_tasks_path(target_user)
    else
      stafftools_path
    end
  end
end
