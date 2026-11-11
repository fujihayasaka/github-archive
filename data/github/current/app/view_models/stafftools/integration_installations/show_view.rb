# typed: true
# frozen_string_literal: true

class Stafftools::IntegrationInstallations::ShowView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  include GitHub::Memoizer

  attr_reader :installation, :repositories, :user

  delegate :integration, :target, :rate_limit, :using_temporary_rate_limit?, :outdated?, to: :installation
  delegate :integrator_suspended?, :integrator_suspended_at, :user_suspended?, :user_suspended_at, :user_suspended_by, to: :installation

  def installed_at
    installation.created_at
  end

  def page_title
    "#{ target } - #{ integration.name }"
  end

  def selected_link
    :installations
  end

  def ghec_rate_limit
    ghec_rate_limit_config.limit
  end

  def ghec_rate_limit_runway
    ghec_rate_limit_config.runway
  end

  memoize def installed_on_all_repositories?
    installation.cached_installed_on_all_repositories?
  end

  def repository_access_text
    prefix = "Installed on"
    suffix = installed_on_all_repositories? ? "all repositories" : "a subset or no repositories"

    "Installed on #{suffix}"
  end

  memoize def outdated_installation_message
    version_count = integration.latest_version.number - installation.integration_version_number
    "This installation of #{integration.name} is #{helpers.pluralize(version_count, 'version')} behind. It may be missing permissions or hook event subscriptions."
  end

  memoize def subscribed_events_sentence
    prefix = "Subscribed to:"
    return "#{prefix} no events." if installation.events.none?

    events = installation.events.map do |event_type|
      Hook::EventRegistry.for_event_type(event_type)
    end.sort_by(&:display_name).map(&:display_name).to_sentence

    "#{prefix} #{events}."
  end

  memoize def orphan?
    return false unless installation.integration.private_visibility?
    installation.target != integration.owner
  end

  memoize def orphan_installation_message
    "NOTE: This installation is an orphan. After it was installed, the owner transferred the app to another owner. The app visibility is private though, which means the target of this installation can't see the app anymore. Consider asking the installation owner to uninstall the app if it's not operating correctly."
  end

  private

  def ghec_rate_limit_config
    @ghec_rate_limit_config ||= begin
      context = Stafftools::RateLimitContext.new(
        nil,
        current_integration_installation: installation,
        request_owner: target,
      )

      Api::RateLimitConfiguration.for(
        Api::RateLimitConfiguration::DEFAULT_FAMILY,
        context,
      )
    end
  end
end
