# typed: true
# frozen_string_literal: true

class Stafftools::Users::RateLimitsController < StafftoolsController
  before_action :ensure_user_not_org
  before_action :ensure_rate_limiting_enabled

  layout "layouts/stafftools/user/overview"

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show],
    optional: true

  def show
    context = Stafftools::RateLimitContext.new(this_user)
    rate_limits_view = Stafftools::User::RateLimitsView.new(this_user, context)

    render "stafftools/users/rate_limits/show", locals: { view: rate_limits_view }
  end

  def destroy
    context = Stafftools::RateLimitContext.new(this_user)

    Api::RateLimitConfiguration::ALL_FAMILIES.each do |family|
      config = Api::RateLimitConfiguration.for(family, context)
      Api::ConfigThrottler.new(config).remove!
    end

    redirect_to(
      stafftools_user_rate_limits_path(this_user),
      notice: "Rate limits reset for #{this_user}.",
    )
  end

  private

  def ensure_rate_limiting_enabled
    render_404 unless GitHub.rate_limiting_enabled? && !GitHub.enterprise?
  end

  def ensure_user_not_org
    return render_404 if this_user.is_a?(Organization)

    ensure_user_exists
  end
end
