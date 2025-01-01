# typed: true
# frozen_string_literal: true

class Stafftools::UserRestorationsController < StafftoolsController
  before_action :ensure_org_does_not_belong_to_deleted_business

  def create
    account = Stafftools::RestoreAccount.perform(current_user, user_restoration_params.to_h.symbolize_keys)

    if account.valid?
      flash[:notice] = "Account restored"
    else
      flash[:error] = "Unable to restore the account: #{account.errors.full_messages.join(", ")}"
    end

    if params[:return_to].present?
      safe_redirect_to params[:return_to]
    else
      redirect_to stafftools_path
    end
  end

  private

  def user_restoration_params
    params.permit(
      :authenticity_token,
      :id,
      :login,
      :email,
      :plan,
      :was_org,
      :return_to
    )
  end

  def ensure_org_does_not_belong_to_deleted_business
    return unless user = Organization.find_by(id: user_restoration_params[:id])

    if user.belongs_to_a_soft_deleted_business?
      flash[:error] = "This organization is part of a deleted enterprise. It cannot be restored."
      redirect_to stafftools_path
    end
  end
end
