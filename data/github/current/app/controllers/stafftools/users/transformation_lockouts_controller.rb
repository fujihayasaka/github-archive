# typed: true
# frozen_string_literal: true

class Stafftools::Users::TransformationLockoutsController < StafftoolsController
  before_action :ensure_user_exists

  def destroy
    Organization.end_transform(this_user)

    redirect_to(
      stafftools_user_administrative_tasks_path(this_user),
      notice: "Org transform lockout cleared for #{this_user}.",
    )
  end
end
