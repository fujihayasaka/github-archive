# typed: true
# frozen_string_literal: true

module Variables::AppsHelper
  # GitHub apps with org and repo variable management integration.
  ACTIONS_APP_NAME = "actions"
  AGENTS_APP_NAME = "agents"

  # A list of apps that are enabled and visible to the current user.
  def self.enabled_app_names(user, org: nil)
    variables_app_info_hash(user, org:).filter_map { |app_name, app_info| app_name if app_info[:enabled] }.sort
  end

  def self.variables_enabled_for?(app_name, user, org: nil)
    !!variables_app_info_hash(user, org:).dig(app_name, :enabled)
  end

  def self.multi_integrations_enabled_for_user?(user, entity: nil)
    GitHub.dependabot_enabled? || user&.codespaces_feature_enabled? || FeatureFlag.vexi.enabled?(:actions_agent_secrets, entity || user, default: false)
  end

  def self.display_name_for(app_name)
    app_name.capitalize
  end

  def self.page_title_for(app_name, user, entity: nil)
    return "Variables" unless multi_integrations_enabled_for_user?(user, entity:)

    "#{display_name_for(app_name)} variables"
  end

  def self.highlight_for(app_name, user, entity: nil)
    # Variables use the same highlight as secrets.
    # This is because they share the same navigation list.
    return :secrets unless multi_integrations_enabled_for_user?(user, entity:)

    "secrets_settings_#{app_name}".to_sym
  end

  def self.app_for(app_name, user, org: nil)
    variables_app_info_hash(user, org:).dig(app_name, :app)
  end

  # Returns the Variables app integration that should be used to read/write
  # Copilot coding agent (sweagent) repo-level firewall variables
  # (COPILOT_AGENT_FIREWALL_*).
  #
  # When the `actions_agent_secrets` feature flag is enabled for the repo's
  # owner org (or for the user, for user-owned repos), and the agents app is
  # available, those variables live under the agents app. Otherwise they live
  # under the actions app, which is the legacy storage location.
  def self.app_for_repo_firewall(actor, repository)
    org = repository.owner if repository.owner.is_a?(::Organization)
    if agents_enabled?(actor, org)
      agents_app = app_for(AGENTS_APP_NAME, actor, org: org)
      return agents_app if agents_app
    end
    app_for(ACTIONS_APP_NAME, actor, org: org)
  end

  # Returns the app name (string) corresponding to `app_for_repo_firewall`.
  # Useful for building deep-links into the Variables UI for the same app
  # that stores the repo firewall variables.
  def self.app_name_for_repo_firewall(actor, repository)
    org = repository.owner if repository.owner.is_a?(::Organization)
    if agents_enabled?(actor, org) && app_for(AGENTS_APP_NAME, actor, org: org)
      AGENTS_APP_NAME
    else
      ACTIONS_APP_NAME
    end
  end

  def self.variables_app_info_hash(user, org: nil)
    {
      ACTIONS_APP_NAME => {
        app: GitHub.launch_github_app, # Always store variables with the prod app, even in Launch lab.
        enabled: GitHub.actions_enabled?,
      },
      AGENTS_APP_NAME => {
        app: Apps::Privileged.integration(:agent_secrets),
        enabled: agents_enabled?(user, org),
      },
    }
  end

  # TODO(actions-dispatch#425, actions-dispatch#426): At repo level, org is nil so
  # agents is gated by FF only. The controller-level check (Variables::Helper#variables_enabled?)
  # should resolve the repo owner org and pass it here to enforce the CCA check.
  def self.agents_enabled?(entity, org = nil)
    actor = org || entity
    return false unless FeatureFlag.vexi.enabled?(:actions_agent_secrets, actor, default: false)
    return true if org.nil?

    org.copilot_swe_agent_access != Configurable::CopilotSweAgentAccess::State::DISABLED
  end

  private_class_method :variables_app_info_hash
end
