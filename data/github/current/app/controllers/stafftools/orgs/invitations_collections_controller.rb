# typed: true
# frozen_string_literal: true

class Stafftools::Orgs::InvitationsCollectionsController < StafftoolsController
  before_action :dotcom_required
  before_action :ensure_user_exists

  def destroy
    if params[:state] == "failed"
      this_user.destroy_failed_invitations(current_user)
      flash[:notice] = "Enqueued job to delete failed invitations for #{this_user.name}."
      redirect_to :back
    else
      render_404
    end
  end
end
