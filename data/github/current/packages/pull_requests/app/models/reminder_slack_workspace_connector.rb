# typed: false
# frozen_string_literal: true

# Securely connect an organization and user to a Slack workspace via the Slack integration.
class ReminderSlackWorkspaceConnector
  CLOCK_SKEW_LEEWAY = 5.minutes
  VERIFIER_EXPIRATION = 1.hour
  VERIFIER_ID = "reminders_state"

  class Error < StandardError
    def code
      self.class.name.underscore.gsub(/_error\z/, "")
    end
  end

  JwtError                     = Class.new(Error)
  StateMissingError            = Class.new(Error)
  StateMismatchError           = Class.new(Error)
  WorkspaceParamsMissingError  = Class.new(Error)
  InsufficientPermissionsError = Class.new(Error)
  SlackIntegrationError        = Class.new(Error)
  SelectedEnterpriseInRemindersError = Class.new(Error)
  IntegrationMissingError      = Class.new(Error)

  def self.encrypt(state)
    JWT.encode(state, GitHub.slack_integration_secret, "HS256")
  end

  def self.decrypt(encrypted_state)
    state, _ = begin
      JWT.decode(encrypted_state, GitHub.slack_integration_secret, true, {
        algorithm: "HS256",
        verify_iat: true,
        verify_iss: true,
        leeway: CLOCK_SKEW_LEEWAY,
      })
    rescue JWT::DecodeError, JWT::ExpiredSignature
      raise JwtError
    end
    state
  end

  attr_reader :user, :organization
  attr_accessor :workspace, :referring_path, :error, :enterprise_name
  def initialize(user:, organization:)
    @user = user
    @organization = organization
  end

  def authorization_url(referring_path:, redirect_url:)
    state = {
      "referring_path" => referring_path,
      "user_id" => user.id,
      "organization_id" => organization.id,
      "salt" => SecureRandom.uuid,
      "time" => Time.now.utc.iso8601,
    }

    if GitHub.multi_tenant_enterprise? && !GitHub::CurrentTenant.get
      raise "Can't generate proper authorization url in multi-tenant mode without tenant context"
    end

    if GitHub.flipper[:global_slack_proxima_routing].enabled?
      url = URI(GitHub.slack_integration_global_api_url)
    else
      url = URI(GitHub.slack_integration_api_url)
    end

    url.path = GitHub.enterprise? ? "/_slack/slack/v2/oauth/login/both" : "/slack/v2/oauth/login/both"
    query_params = {
      redirect_uri: redirect_url,
      github_org: organization,
      github_org_id: organization.id,
      state: self.class.encrypt(state),
    }
    if GitHub.multi_tenant_enterprise?
      query_params[:tenant] = GitHub::CurrentTenant.get.slug
    end
    url.query = query_params.to_query
    url.to_s
  end

  def connect(jwt)
    workspace_params, _ = begin
      JWT.decode(jwt, GitHub.slack_integration_secret, true, {
        algorithm: "HS256",
        verify_iat: true,
        verify_iss: true,
        leeway: CLOCK_SKEW_LEEWAY,
      })
    rescue JWT::DecodeError, JWT::ExpiredSignature
      raise JwtError
    end

    raise SlackIntegrationError.new(workspace_params["error"]) if workspace_params["error"]
    raise StateMissingError if workspace_params["state"].nil? # state.nil?
    # state is implicitly signed within the JWT
    # Verify the same user/org that left in the original redirect from authorize action
    state = self.class.decrypt(workspace_params["state"])
    self.referring_path = state && state["referring_path"]
    self.enterprise_name = workspace_params["enterprise_name"]
    raise SelectedEnterpriseInRemindersError if workspace_params["enterprise_install"] == true
    raise StateMismatchError if state["user_id"] != user.id || state["organization_id"] != organization.id
    raise WorkspaceParamsMissingError if workspace_params["workspace_id"].blank? || workspace_params["workspace_name"].blank?
    raise InsufficientPermissionsError unless sufficient_permissions?(workspace_params["workspace_id"])

    self.workspace = ReminderSlackWorkspace.create_or_update_workspace(
      name: workspace_params["workspace_name"],
      remindable: organization,
      slack_id: workspace_params["workspace_id"],
    )

    ReminderSlackWorkspaceMembership.create_or_update_membership(
      user_id: user.id,
      reminder_slack_workspace_id: workspace.id,
    )
  end

  def self.slack_integration
    Apps::Privileged.integration(:slack) || raise(IntegrationMissingError, "Slack Integration did not exist")
  end

  private

  def sufficient_permissions?(workspace_slack_id)
    return true if organization.adminable_by?(user)

    workspace_already_exists = ReminderSlackWorkspace.where(
      remindable: organization,
      slack_id: workspace_slack_id,
    ).exists?

    organization.member?(user) && workspace_already_exists
  end
end
