# typed: true
# frozen_string_literal: true

class Stafftools::Users::RateLimits::OverridesController < StafftoolsController
  before_action :ensure_user_not_org

  def update
    this_user.toggle_content_creation_rate_limit_allowlisted(allowlister: current_user)

    redirect_to stafftools_user_administrative_tasks_path(this_user)
  end

  private

  def ensure_user_not_org
    return render_404 if this_user.is_a?(Organization)

    ensure_user_exists
  end
end
