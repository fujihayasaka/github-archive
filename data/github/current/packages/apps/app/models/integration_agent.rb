# typed: false
# frozen_string_literal: true

class IntegrationAgent < ApplicationRecord::Domain::Copilot
  include Instrumentation::Model

  extend GitHub::Encoding
  force_utf8_encoding :description

  # Inspired by Webhooks' patterns
  DISALLOWED_HOSTS_PATTERNS = [
    Regexp.new("\\A(.*\\.)?github\\.net\.?\\z", Regexp::IGNORECASE),
    Regexp.new("\\A(.*\\.)?consul\.?\\z", Regexp::IGNORECASE),
  ].freeze
  LOOPBACK_HOSTS_PATTERN = [
    Regexp.new("\\A(.*\\.)?localhost\\z", Regexp::IGNORECASE),
    Regexp.new("\\A(127|0)\.(?=.*[^\.]$)((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.?){3}\\z", Regexp::IGNORECASE), # match all ip addresses in the 0.0.0.0/8 and 127.0.0.1/8 range
  ].freeze
  # List of internal hosts that are allowed to be used in the URL field
  # despite matching the DISALLOWED_HOSTS_PATTERNS
  INTERNAL_HOST_OVERRIDE = [
    "copilot-agents-production.service.iad.github.net",
    "github-models-extension-production.service.iad.github.net",
  ]

  belongs_to :integration

  attribute :client_authorization_url, :string, default: ""

  validates :integration, presence: true
  validate :description_is_valid
  validate :url_is_valid
  validate :client_authorization_url_is_valid, unless: -> { client_authorization_url.blank? }

  # Returns an array of integrations that the user is authorized to use as an agent.
  # An authorized integration must be configured as an agent.
  def self.integrations_authorized_for_user(user)
    ids = user.authorizations_for_kind("github_apps").select(:application_id)
    apps = Integration.includes(:integration_agent).where(id: ids)
    apps.filter { |app| app.agent_configured? }
  end

  # Returns an array of integrations that the user owns and can access as an agent.
  def self.integrations_owned_by_user(user)
    apps = Integration.includes(:integration_agent).where(owner_id: user.id)
    apps.filter { |app| app.agent_configured? }
  end

  # Returns an array of integration agents that are public.
  def self.public_integrations
    integration_agents = IntegrationAgent.includes(integration: { latest_version: [:default_permission_records] }).all.filter do |agent|
      agent.integration.public? && agent.integration&.agent_configured?
    end
    integration_agents.map { |agent| agent.integration }
  end

  # Returns an array of integrations that are installed for the given target that are configured as agents.
  def self.integrations_installed_for_target(target)
    version_ids = target.integration_installations.select(:integration_version_id)
    versions = IntegrationVersion.includes(:default_permission_records, integration: [:integration_agent])
      .where(id: version_ids)

    versions.filter do |version|
      version.integration && version.integration.agent_configured?(version)
    end.map(&:integration)
  end

  # Returns an array of integrations that are installed for the given organizations that are configured as agents.
  # This is for_orgs and not for_targets because targets creates a cross-domain subquery.
  def self.integrations_installed_for_orgs(orgs)
    version_ids = IntegrationInstallation.select(:integration_version_id)
      .where(target_type: "User", target_id: orgs.map(&:id))
    versions = IntegrationVersion.includes(:default_permission_records, integration: [:integration_agent])
      .where(id: version_ids)

    versions.filter do |version|
      version.integration && version.integration.agent_configured?(version)
    end.map(&:integration)
  end

  def url_is_valid
    url_string_is_valid?(url)
  end

  def client_authorization_url_is_valid
    url_string_is_valid?(client_authorization_url)
  end

  def url_string_is_valid?(u)
    if u.blank?
      errors.add(:url, "Config must contain a URL")
      return
    end

    if u.strip != u
      errors.add(:url, "The URL should not start or end with a space")
      return
    end

    begin
      uri = URI(u)
    rescue URI::InvalidURIError
      errors.add(:url, "The URL you've entered is not valid. Please make sure that you encode all special characters first")
      return
    end

    if uri.scheme.nil?
      errors.add(:url, "Config URL is missing a scheme")
      return
    end

    unless uri.scheme =~ /https?/
      errors.add(:url, "Config URL scheme is invalid")
      return
    end

    unless UrlHelper.valid_host?(uri.host)
      errors.add(:url, "Config URL host is invalid")
      return
    end

    if LOOPBACK_HOSTS_PATTERN.any? { |pattern| !!pattern.match(uri.host) }
      errors.add(:url, "Sorry, the URL host #{uri.host} is not supported because it isn't reachable over the public Internet")
      return
    end

    unless INTERNAL_HOST_OVERRIDE.include?(uri.host) && integration&.feature_enabled?(:copilot_agent_allow_host_override)
      if DISALLOWED_HOSTS_PATTERNS.any? { |pattern| !!pattern.match(uri.host) }
        errors.add(:url, "Config URL host is not allowed")
        return
      end
    end

    uri
  end

  def description_is_valid
    self.errors.add :description, "Config must contain a description" if self.description.nil?
  end
end
