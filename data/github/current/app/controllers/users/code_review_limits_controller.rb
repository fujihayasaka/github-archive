# typed: true
# frozen_string_literal: true

class Users::CodeReviewLimitsController < Users::Controller
  before_action :require_feature
  before_action :login_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show],
    optional: true

  def show
    render "users/code_review_limits/show"
  end

  def update
    case params[:limit]
    when "enable"
      current_user.restrict_non_comment_pull_request_reviews(actor: current_user, override: true)
    when "disable"
      current_user.unrestrict_non_comment_pull_request_reviews(actor: current_user, override: true)
    when "unset"
      current_user.unset_non_comment_pull_request_reviews(actor: current_user)
    end

    flash[:notice] = "Code review limit settings saved."
    redirect_to settings_user_code_review_limits_path
  end

  private

  def target_for_conditional_access
    # Anonymous requests will be denied by :login_required.
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess

    current_user
  end

  def require_feature
    render_404 unless GitHub.code_review_limits_enabled?
  end
end
