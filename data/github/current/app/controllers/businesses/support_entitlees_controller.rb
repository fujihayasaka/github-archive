# typed: true
# frozen_string_literal: true

class Businesses::SupportEntitleesController < Businesses::BusinessController
  before_action :business_owner_required
  before_action :dotcom_required

  def create
    if user = User.find_by(login: params[:user])
      this_business.add_support_entitlee(user, actor: current_user)
      redirect_to enterprise_support_index_path(this_business), notice: "Added support member #{user.display_login}."
    else
      flash.now[:error] = "Something went wrong."
      render "businesses/settings/support", locals: { entitlees: support_entitlees }
    end
  end

  def destroy
    if user = User.find_by(id: params[:id].to_i)
      this_business.remove_support_entitlee(user, actor: current_user)
      redirect_to enterprise_support_index_path(this_business), notice: "Removed support member #{user.display_login}."
    else
      flash.now[:error] = "Something went wrong."
      render "businesses/settings/support", locals: { entitlees: support_entitlees }
    end
  end

  private

  memoize def support_entitlees
    this_business.support_entitlees.includes(:profile)
  end
end
