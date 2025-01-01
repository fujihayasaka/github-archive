# typed: true
# frozen_string_literal: true

class Stafftools::Users::MaxPackagesAuthorizablePerTokenController < StafftoolsController

  def update
    return render_404 unless GitHub.flipper[:max_packages_authorizable_per_token].enabled?

    new_value = params[:max_packages]&.to_i || 0
    this_user.set_max_packages_authorizable_per_token(new_value, current_user)

    if this_user.max_packages_authorizable_per_token == new_value
      flash[:notice] = "Max packages authorizable per token saved"
    else
      flash[:error] = "Failed to save max packages authorizable per token"
    end

    redirect_to stafftools_user_administrative_tasks_path(this_user)
  end
end
