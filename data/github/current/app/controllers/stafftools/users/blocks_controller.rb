# typed: true
# frozen_string_literal: true

class Stafftools::Users::BlocksController < StafftoolsController
  before_action :ensure_user_exists
  before_action :ensure_target_user_exists

  def create
    ignored_user = this_user.block(target_user, actor: current_user)

    if ignored_user.valid?
      instrument(
        "staff.block_user",
        user: this_user,
        blocked_user: target_user.display_login,
        blocked_user_id: target_user.id,
      )

      redirect_to(
        stafftools_user_interactions_path(this_user),
        notice: "Blocking #{target_user.login} on behalf of #{this_user.login}.",
      )
    else
      redirect_to(
        stafftools_user_interactions_path(this_user),
        flash: { error: "Unable to block #{target_user.login} on behalf of #{this_user.login}." },
      )
    end
  end

  def destroy
    this_user.unblock(target_user, actor: current_user)
    instrument(
      "staff.unblock_user",
      user: this_user,
      unblocked_user: target_user.display_login,
      unblocked_user_id: target_user.id,
    )

    redirect_to(
      stafftools_user_interactions_path(this_user),
      notice: "#{this_user.login} is no longer ignoring #{target_user.login}.",
    )
  end

  private

  def ensure_target_user_exists
    unless target_user
      redirect_to(
        stafftools_user_interactions_path(this_user),
        flash: { error: "Whoops. There isn't anyone called #{params[:login]}." },
      )
    end
  end

  def target_user # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @_target_user if defined?(@_target_user)

    @_target_user = User.find_by(login: params[:login])
  end
end
