# typed: true
# frozen_string_literal: true

class Devtools::SpamuraiController < DevtoolsController # rubocop:todo GitHub/ControllersShouldHaveTests
  before_action :login_required
  before_action :sudo_filter

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:dashboard]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:dashboard],
    optional: true

  def dashboard # rubocop:todo GitHub/UseRestfulActions
    render "devtools/spamurai/dashboard"
  end

  private

  def set_default_nav_breadcrumb
    return unless header_redesign_enabled?
    set_nav_breadcrumb ContextRegion::Devtools::SpamuraiCrumb.new
  end
end
