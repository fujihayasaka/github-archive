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
      ApplicationRecord::Copilot,
      only: [:index]

    before_action :login_required
    before_action :require_feature_enabled
    before_action :require_mcp_policy_enabled

    PER_PAGE = 10

    def index
      server_configs = CopilotMcp::Query.search_mcp_server_configs_for_user(current_user, name: params[:server_name].presence)
      .paginate(page: current_page, per_page: PER_PAGE)

      paginated_infos = server_configs.map do |config|
        {
          id: config.id,
          display_name: config.display_name.presence || config.mcp_server&.name || "Unknown Server",
          created_at: config.created_at
        }
      end

      render "settings/mcp/index", locals: {
        registered_servers: paginated_infos,
        total_count: server_configs.total_entries,
        page: current_page,
        total_pages: server_configs.total_pages
      }
    end

    private

    def current_page
      page = params[:page].to_i
      page.positive? ? page : 1
    end

    def require_feature_enabled
      render_404 unless user_feature_enabled?(:copilot_api_dotcom_chat_use_third_party_mcp_servers)
    end

    def require_mcp_policy_enabled
      copilot_user = ::Copilot::User.new(current_user)
      render_404 unless copilot_user.mcp_enabled?
    end

  end
end
