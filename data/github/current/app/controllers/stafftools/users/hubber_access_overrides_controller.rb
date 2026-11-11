# typed: true
# frozen_string_literal: true

class Stafftools::Users::HubberAccessOverridesController < StafftoolsController
  before_action :ensure_user_exists
  skip_before_action :prompt_for_hubber_access unless GitHub.enterprise?

  def create
    if params[:reason].present?
      current_user.set_hubber_access_reason(this_user, params[:reason])
      flash[:notice] = "The staff user #{this_user} has been unlocked for #{current_user}."
    else
      flash[:error] = "You must provide a reason to unlock a staff account."
    end

    redirect_to stafftools_user_overview_path(this_user)
  end
end
