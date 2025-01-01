# typed: true
# frozen_string_literal: true

class Stafftools::Users::GitHubBiztoolsPromotionsController < StafftoolsController
  before_action :ensure_user_exists
  before_action :ensure_billing_enabled

  def create
    if this_user.grant_github_biztools_access(params[:reason])
      flash[:notice] = "#{this_user} promoted to GitHub biztools user."
    else
      flash[:error] = "You have to specify a reason for the log."
    end

    redirect_to stafftools_user_administrative_tasks_path(this_user)
  end

  private

  def ensure_billing_enabled
    render_404 unless GitHub.billing_enabled?
  end
end
