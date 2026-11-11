# typed: true
# frozen_string_literal: true

class Hook::Event::InstallationRepositoriesEvent < Hook::Event
  supports_targets Integration
  auto_subscribed
  description "Repositories changed on installation"

  event_attr :action, :installation_id, required: true
  event_attr :repositories_added, :repositories_removed, :actor_id, :repository_selection, :requester_id

  def actor
    @actor ||= User.find_by(id: actor_id) || User.ghost
  end

  def installation
    @installation ||= IntegrationInstallation.includes(:integration).find(installation_id)
  end

  def integration
    installation.integration
  end

  def subscribed_hooks
    return [] unless integration&.active_and_subscribable?

    # Dependabot consumes installation-related events via hydro so we should
    # skip producing hooks since their payload is costly to generate
    return [] if integration.dependabot_github_app?

    [integration.hook]
  end

  def requester
    return @requester if defined?(@requester)
    @requester = User.find_by(id: requester_id)
  end

  def deliverable?
    repositories_removed&.present? || repositories_added&.present?
  end
end
