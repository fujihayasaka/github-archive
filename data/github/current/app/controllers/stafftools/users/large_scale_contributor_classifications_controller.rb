# typed: true
# frozen_string_literal: true

class Stafftools::Users::LargeScaleContributorClassificationsController < StafftoolsController
  before_action :ensure_user_exists

  def update
    if this_user.large_scale_contributor?
      this_user.remove_large_scale_contributor_flag!(actor: current_user)
      flash[:notice] = "Successfully removed large-scale contributor flag for #{this_user}."
    else
      this_user.flag_as_large_scale_contributor!(actor: current_user)
      flash[:notice] = "Successfully flagged #{this_user} as a large-scale contributor."
    end

    redirect_to stafftools_user_administrative_tasks_path(this_user)
  end
end
