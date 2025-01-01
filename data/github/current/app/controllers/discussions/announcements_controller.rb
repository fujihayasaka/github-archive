# typed: true
# frozen_string_literal: true

class Discussions::AnnouncementsController < Discussions::BaseController
  before_action :login_required, only: %i(destroy)
  before_action :current_user_can_read_repo?, only: %i(destroy)
  skip_before_action :require_feature

  def destroy
    dismiss_popover

    if user_wants_to_turn_on_discussions?
      current_repository = T.must_because(self.current_repository) { "#current_user_can_read_repo? ensures non-nil" }
      redirect_to edit_repository_path(current_repository.owner, current_repository, anchor: "features")
    else
      head :ok
    end
  end

  private

  def dismiss_popover
    current_user.dismiss_discussions_announcement
    current_user.dismiss_private_repo_discussions_announcement
  end

  def user_wants_to_turn_on_discussions?
    params[:next] == "redirect"
  end
end
