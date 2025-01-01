# typed: true
# frozen_string_literal: true

class Stafftools::Users::FollowsController < StafftoolsController
  before_action :ensure_user_exists

  def destroy
    if target_user
      this_user.unfollow(target_user)
      instrument(
        "staff.unfollow_user",
        user: this_user,
        unfollowed_user: target_user.display_login,
        unfollowed_user_id: target_user.id,
      )
      flash[:notice] = "Unfollowed #{target_user} on behalf of #{this_user}."
    else
      flash[:error] = "Whoops. There isn't anyone called #{params[:login]}."
    end

    redirect_to stafftools_user_interactions_path(this_user)
  end

  private

  memoize def target_user
    User.find_by(login: params[:login])
  end
end
