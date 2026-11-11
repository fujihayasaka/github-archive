# typed: true
# frozen_string_literal: true

class CopilotSessions::AgentQuotaSnapshotsController < ApplicationController
  include ApplicationController::VerifiedFetchDependency

  before_action :login_required
  allow_verified_fetch only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Copilot,
    ApplicationRecord::Collab,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    ApplicationRecord::Permissions

  def show
    render json: {
      agentQuotaSnapshot: Copilot::Users::AgentQuotaSnapshot.new.build(user: T.must(current_user))
    }
  end

  private

  def target_for_conditional_access
    current_user
  end
end
