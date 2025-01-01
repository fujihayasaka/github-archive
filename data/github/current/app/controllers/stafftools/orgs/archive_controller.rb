# typed: true
# frozen_string_literal: true

class Stafftools::Orgs::ArchiveController < Stafftools::UsersController
  before_action :ensure_user_exists
  before_action :organization_required

  def create
    if this_user.archive(current_user, by_site_admin: true)
      flash[:notice] = "The #{this_user.display_login} organization is being archived."
    else
      flash[:error] = "The #{this_user.display_login} organization cannot be archived at this time."
    end

    redirect_to :back
  end

  def destroy
    if this_user.unarchive(current_user)
      flash[:notice] = "The #{this_user.display_login} organization is being unarchived."
    else
      flash[:error] = "The #{this_user.display_login} organization cannot be unarchived at this time."
    end

    redirect_to :back
  end

  private

  def organization_required
    render_404 unless this_user.organization?
  end
end
