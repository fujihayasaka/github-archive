# typed: true
# frozen_string_literal: true

class Businesses::PreReceiveHooksController < Businesses::BusinessController
  before_action :enterprise_required
  before_action :business_owner_required
  before_action :require_custom_pre_receive_hooks_enabled

  def destroy
    @hook = PreReceiveHook.find_by(id: params[:id])
    if T.must(@hook).destroy
      flash[:notice] = "Successfully deleted hook"
      redirect_to hooks_enterprise_path(GitHub.global_business)
    else
      flash[:error] = "Error deleting hook"
      redirect_to hooks_enterprise_path(GitHub.global_business)
    end
  end

end
