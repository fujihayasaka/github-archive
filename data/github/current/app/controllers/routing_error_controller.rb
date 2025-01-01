# typed: true
# frozen_string_literal: true

class RoutingErrorController < ApplicationController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Authnd,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  # CAP not required, shows static 404 page
  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  def index
    render_404
  end
end
