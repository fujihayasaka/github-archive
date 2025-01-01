# typed: true
# frozen_string_literal: true

class Stafftools::ModelsBlocksController < StafftoolsController
  before_action :dotcom_required
  before_action :require_reason

  def create
    success = GitHubModels.domain.blocks.create(
      actor: current_user,
      user: this_user,
      reason: "#{params[:reason]} #{params[:additional_information]}".strip,
    )
    if success
      flash[:notice] = "@#{this_user.display_login} has been blocked from GitHub Models."
    else
      flash[:error] = "Failed to block @#{this_user.display_login} from GitHub Models, see " \
      "#{GitHubModels.domain.blocks.notification_slack_channel} in Slack for details."
    end
    redirect_to stafftools_user_models_path(this_user.display_login)
  end

  def destroy
    GitHubModels.domain.blocks.destroy(actor: current_user, user: this_user, reason: params[:reason])
    flash[:notice] = "Restored GitHub Models access to @#{this_user.display_login}."
    redirect_to stafftools_user_models_path(this_user.display_login)
  end

  private

  def require_reason
    if params[:reason].blank?
      action_description = action_name == "create" ? "blocking" : "unblocking"
      flash[:error] = "Please provide a reason for #{action_description} @#{this_user.display_login}."
      redirect_to stafftools_user_models_path(this_user.display_login)
    end
  end
end
