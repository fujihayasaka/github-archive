# typed: true
# frozen_string_literal: true

class Hook::Event::InstallationEvent < Hook::Event
  supports_targets Integration
  auto_subscribed
  description "GitHub App installed, uninstalled, suspended, or unsuspended."

  event_attr :action, :installation_id, :integration_id, :actor_id, required: true
  event_attr :requester_id,                                         required: false

  def subscribed_hooks
    return [] unless integration.active_and_subscribable?

    # Dependabot consumes installation-related events via hydro so we should
    # skip producing hooks since their payload is costly to generate
    return [] if integration.dependabot_github_app?

    [integration.hook]
  end

  def actor
    @actor ||= User.find(actor_id)
  end

  def installation
    @installation ||= IntegrationInstallation.find(installation_id)
  end

  def integration
    @integration ||= Integration.find(integration_id)
  end

  def repository_selection
    installation.repository_selection
  end

  def repositories
    installation.repositories
  end

  def requester
    return @requester if defined? @requester
    @requester = User.find_by(id: requester_id)
  end
end
