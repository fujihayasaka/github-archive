# typed: true
# frozen_string_literal: true

class Repos::AgentSessionsController < AbstractRepositoryController
  before_action :require_copilot_swe_agent_enabled

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
  only: [:index, :show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :show],
    optional: true

  def index
    render_react_app(
      data_router_enabled: true,
      payload: {
        listSessionsRoute: {
          title: "ListSessions",
          mainQuery: {
            repository: repo_data,
            sessions: mock_data,
          }
        }
      }
    )
  end

  def show
    render_react_app(
      data_router_enabled: true,
      payload: {
        showSessionRoute: {
          title: "ShowSession",
          mainQuery: {
            repository: repo_data,
            session: mock_data[0],
          }
        }
      },
    )
  end

  private

  def require_copilot_swe_agent_enabled
    render_404 unless current_repository.copilot_swe_agent_enabled?
  end

  # Mock data until we're fetching from CAPI
  def mock_data
    [{
      "id": "1d77c96b-52e9-41a6-9a60-4e27b3f5b72e",
      "user_id": current_user.id,
      "agent_id": Apps::Privileged.integration(:copilot_swe_agent).id,
      "state": "created",
      "owner_id": current_repository.owner_id,
      "repo_id": current_repository.id,
      "resource_type": "issues",
      "resource_id": 123,
      "created_at": "2025-03-17T12:04:35-04:00",
      "last_updated_at": "2025-03-17T12:04:35-04:00",
   }]
  end

  def repo_data
    { ownerLogin: current_repository.owner.display_login, name: current_repository.name }
  end
end
