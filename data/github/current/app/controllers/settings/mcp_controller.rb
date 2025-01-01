# typed: true
# frozen_string_literal: true

module Settings
  class McpController < ApplicationController
    include Settings::ControllerMethods

    depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Copilot,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Billing,
    only: [:index]

    before_action :login_required
    before_action :require_feature_enabled

    def index
      registered_servers = GetServersForUser.call(user: current_user)
      render "settings/mcp/index", locals: {
        registered_servers: registered_servers,
      }
    end

    private

    def require_feature_enabled
      render_404 unless user_feature_enabled?(:copilot_mcp)
    end
  end
end
