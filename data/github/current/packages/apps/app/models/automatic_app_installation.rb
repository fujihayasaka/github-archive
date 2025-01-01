# typed: true
# frozen_string_literal: true

class AutomaticAppInstallation

  TRIGGER_HANDLERS = {
    file_added: AutomaticAppInstallation::Handlers::FileAdded,
    user_created: AutomaticAppInstallation::Handlers::UserCreated,
    team_sync_enabled: AutomaticAppInstallation::Handlers::TeamSyncEnabled,
    automatic_security_updates_initialized: AutomaticAppInstallation::Handlers::AutomaticSecurityUpdatesInitialized,
    dependency_graph_initialized: AutomaticAppInstallation::Handlers::DependencyGraphInitialized,
    dependency_update_requested: AutomaticAppInstallation::Handlers::DependencyUpdateRequested,
    page_build: AutomaticAppInstallation::Handlers::PageBuild,
    pending_dependabot_installation_requested: AutomaticAppInstallation::Handlers::PendingDependabotInstallationRequested,
    button_clicked: AutomaticAppInstallation::Handlers::ButtonClicked,
    oauth_code_exchanged: AutomaticAppInstallation::Handlers::OauthCodeExchanged,
    dependabot_repository_access_updated: AutomaticAppInstallation::Handlers::DependabotRepositoryAccessUpdated,
    actions_automatic_installation: AutomaticAppInstallation::Handlers::ActionsAutomaticInstallation,
  }.freeze

  def self.trigger(type:, originator:, actor:, async: true)
    GitHub.dogstats.increment("automatic_app_installation.triggered", tags: ["trigger:#{type}", "async:#{async}"])
    # currently the async implementation publishes to an in-process queue which
    # calls back to `::attempt_installation`.
    if async
      GlobalInstrumenter.instrument("integration_install", trigger_type: type, originator: originator, actor: actor)
    else
      attempt_installation(trigger: type, originator: originator, actor: actor)
    end
  end

  # Internal: called by the subscriber, this method matches a named trigger to
  # the relevant handler and requests the App be installed.
  def self.attempt_installation(trigger:, originator:, actor:)
    install_triggers = IntegrationInstallTrigger.by_install_type(trigger)
    handler = TRIGGER_HANDLERS.fetch(trigger).new(
      install_triggers: install_triggers,
      originator: originator,
      actor: actor
    )

    result = handler.validate
    if result.success?
      GitHub.dogstats.increment(
        "automatic_app_installation.attempt_installation",
        tags: ["trigger:#{trigger}"],
      )
      handler.install_integration
    else
      GitHub.dogstats.increment(
        "automatic_app_installation.handler_validation_failed",
        tags: ["trigger:#{trigger}", "reason:#{result.reason}"],
      )
    end

    [result]
  end
end
