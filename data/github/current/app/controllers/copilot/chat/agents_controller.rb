# typed: true
# frozen_string_literal: true

class Copilot::Chat::AgentsController < Copilot::Chat::AbstractChatController
  allow_verified_fetch only: [:show]

  include CopilotChatHelper

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Billing,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Copilot,
    ApplicationRecord::Mysql5,
    only: [:show]

  def show
    headers["Cache-Control"] = "max-age=60"
    render json: agents
  end

  private

  def agents
    if feature_enabled_globally_or_for_current_user?(:copilot_chat_get_agents_from_capi)
      return [] unless capi

      capi.agents[:agents].map do |agent|
        # the client is expecting this shape, so this is a temporary fix until we move this logic all to the client side
        agent[:integrationUrl] = agent[:url]
        agent[:avatarUrl] = agent[:avatar_url]
        agent
      end
    else
      get_chat_agents(sso_organizations)
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
