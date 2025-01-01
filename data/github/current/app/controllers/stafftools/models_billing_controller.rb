# typed: true
# frozen_string_literal: true

class Stafftools::ModelsBillingController < StafftoolsController
  before_action :dotcom_required

  sig { void }
  def create
    if this_user.enable_models_billing(current_user)
      flash[:notice] = "Models billing has been enabled for #{this_user.login}"
    else
      flash[:error] = "Failed to enable models billing for #{this_user.login}"
    end

    redirect_back(fallback_location: stafftools_user_models_url(this_user))
  end

  sig { void }
  def destroy
    if this_user.disable_models_billing(current_user)
      flash[:notice] = "Models billing has been disabled for #{this_user.login}"
    else
      flash[:error] = "Failed to disable models billing for #{this_user.login}"
    end

    redirect_back(fallback_location: stafftools_user_models_url(this_user))
  end
end
