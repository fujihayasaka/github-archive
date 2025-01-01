# typed: true
# frozen_string_literal: true

class Stafftools::Orgs::SoftDeletionController < Stafftools::UsersController
  def create
    this_user.soft_delete!(current_user, site_admin_deletion: true)
    flash[:notice] = "Deleted #{this_user.name}."

    redirect_to stafftools_user_administrative_tasks_path(this_user)
  end
end
