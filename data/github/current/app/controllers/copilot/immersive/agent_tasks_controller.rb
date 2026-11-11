# typed: true
# frozen_string_literal: true

class Copilot::Immersive::AgentTasksController < Copilot::ImmersiveController
  include MissionControlExperimentEvents

  DECOUPLED_PR_EXPERIMENT = AzureEXP::Experiments::MissionControlDecoupledPr

  depends_on_clusters(
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Copilot,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    only: [:show, :user_access_denied]
  )

  def user_access_denied # rubocop:disable GitHub/UseRestfulActions
    context_region_preset :copilot

    # Redirect to the Agents page in case the user was shown the access denied page, got access, and then reloads the page
    # Also redirect to display an empty state prompting the user to request access from their admin if policy is disabled
    redirect_to copilot_agent_tasks_show_path
  end

  def show
    user = current_user

    if user
      # Skip exposure for staff-shipped users — they get the feature via the staff ship flag
      # and should not pollute experiment data. Does not handle treatment assignment at this stage.
      unless user.feature_flag_enabled?(DECOUPLED_PR_EXPERIMENT::STAFF_SHIP_FEATURE_FLAG, default: false)
        emit_experiment_exposure(
          surface_type: :AGENT_SURFACE_TYPE_IMMERSIVE,
          entry_point: "immersive_agent_tasks",
          experiment: DECOUPLED_PR_EXPERIMENT,
        )
      end
    end

    super
  end

  private

  memoize def agent_tasks_enabled?
    Copilot::Public::User.for(current_user).swe_agent_enabled?
  end

  memoize def use_token_based_billing?
    Copilot::Public::User.for(current_user).use_token_based_billing?
  end

  def app_payload
    user = T.must(current_user)

    token = if agent_tasks_enabled?
      CopilotSessions::CopilotApiToken.get_encrypted(
        user: user,
        entry_point: :agent_tasks_controller_show,
        user_session: user_session
      )
    end

    # Call the base class method to get the default payload
    payload = super.merge({
      sessionsPollingInterval: CopilotSessions::Public.copilot_sessions_polling_interval_seconds.value * 1000.0,
      logsPollingInterval: CopilotSessions::Public.copilot_logs_polling_interval_seconds.value * 1000.0,
      currentUser: CopilotSessions::Payloads::PublicUser.new(user).call,
      useTokenBasedBilling: use_token_based_billing?,
    })

    # Include the SSR-generated auth token so the client can store it
    # This avoids the client needing to fetch a new token on page load
    if token
      payload[:initialAuthToken] = {
        token: token.value,
        expiration: token.expiration&.iso8601,
        ssoOrgIDs: saml_for_user.protected_organization_ids.map(&:to_s)
      }
    end

    payload
  end
end
