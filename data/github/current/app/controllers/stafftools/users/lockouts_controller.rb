# typed: true
# frozen_string_literal: true

class Stafftools::Users::LockoutsController < StafftoolsController
  before_action :ensure_user_exists

  def destroy
    AuthenticationLimit.clear_data(AuthenticationLimit.all_data_for_login(this_user.login))

    redirect_to(
      stafftools_user_administrative_tasks_path(this_user),
      notice: "#{this_user} unlocked",
    )
  end
end
