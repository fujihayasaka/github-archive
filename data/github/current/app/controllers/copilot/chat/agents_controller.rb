# typed: true
# frozen_string_literal: true

class Copilot::Chat::AgentsController < Copilot::Chat::AbstractChatController
  allow_verified_fetch only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Billing,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Copilot,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:show]

  def show
    headers["Cache-Control"] = "max-age=60"
    render json: agents
  end

  private

  def agents
    return [] unless capi

    capi.agents[:agents].map do |agent|
      agent[:integrationUrl] = agent[:url]
      agent[:avatarUrl] = agent[:avatar_url]
      agent
    end
  end

  memoize def capi
    current_user&.copilot_api(integration_id: CopilotAPI::COPILOT_CHAT_INTEGRATION_ID)
  end

  # CAP is not bypassed here as AbstractChatController requires a logged in user
  def target_for_conditional_access
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    current_user
  end
end
