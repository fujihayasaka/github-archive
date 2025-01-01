# typed: true
# frozen_string_literal: true

class Orgs::CodeReviewLimitsController < Orgs::Controller
  before_action :require_feature
  before_action :organization_admin_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Copilot,
    only: [:show]

  def show
    render "orgs/code_review_limits/show"
  end

  def update
    case params[:limit]
    when "enable"
      this_organization.restrict_non_comment_pull_request_reviews(actor: current_user, override: true)
    when "disable"
      this_organization.unrestrict_non_comment_pull_request_reviews(actor: current_user, override: true)
    when "unset"
      this_organization.unset_non_comment_pull_request_reviews(actor: current_user)
    end

    flash[:notice] = "Code review limit settings saved."
    redirect_to settings_org_code_review_limits_path(this_organization)
  end

  private

  def require_feature
    render_404 unless GitHub.code_review_limits_enabled?
  end
end
