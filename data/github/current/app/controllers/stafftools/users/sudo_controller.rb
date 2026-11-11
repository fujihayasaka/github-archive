# typed: true
# frozen_string_literal: true

class Stafftools::Users::SudoController < StafftoolsController
  before_action :ensure_user_exists

  # De-sudo a user's session
  # Should only be available to GH staff
  def destroy
    session_id = params[:id]
    session = this_user.sessions.find_by_id(session_id)

    return render_404 unless session

    session.expire_sudo

    redirect_to :back
  end
end
