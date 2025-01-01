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
    "testdatabot-production.service.iad.github.net",
  ]

  MAX_SKILLS = 5

  Skill = Struct.new(:name, :description, :url, :parameters, :return_type)

  belongs_to :integration

  attribute :client_authorization_url, :string, default: ""

  validates :integration, presence: true
  validate :description_is_valid
  validate :url_is_valid,  if: -> { app_type == "agent" }
  validate :oidc_settings_are_valid, if: -> { token_exchange_enabled == true }
  validate :client_authorization_url_is_valid, unless: -> { client_authorization_url.blank? }
  validate :app_type_is_valid
  validate :skills_are_valid, if: -> { app_type == "skill" }

  # after_commit to avoid cross-cluster queries in the same transaction
  after_commit :update_integration_copilot_status, on: [:create, :update], if: -> { saved_change_to_app_type? }

  def skill_data
    return [] if self[:skill_data].nil?

    JSON.parse(self[:skill_data]).map do |skill|
      Skill.new(skill["name"], skill["description"], skill["url"], skill["parameters"], skill["return_type"])
    end
  end

  def skill_data=(skills)
    skills.each do |skill|
      skill["return_type"] = "string"
    end

    self[:skill_data] = skills.to_json
  end

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
      agent.integration.public_visibility? && agent.integration&.agent_configured?
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

  def app_type_is_valid
    if app_type == "skill" && !self.integration.copilot_extension_skills_enabled?
      errors.add(:app_type, "Skills are not enabled for this integration")
    end
  end

  def skills_are_valid
    skill_data_str = skill_data.is_a?(String) ? skill_data : skill_data.to_s
    if skill_data_str.length > 8000
      errors.add(:skills, "cannot have more than 8000 characters and currently has " + skill_data_str.length.to_s + " characters")
      return
    end

    if skill_data.size > MAX_SKILLS
      errors.add(:skills, "cannot have more than #{MAX_SKILLS} skills")
      return
    end

    skill_data.each do |skill|
      skill_is_valid(skill)
      if errors.size > 0
        return
      end
    end
  end

  def skill_is_valid(skill)

    skill_validation_blank_rules = [
      { invalid: skill.name.blank?, description: "name cannot be blank" },
      { invalid: skill.description.blank?, description: "description cannot be blank" },
      { invalid: skill.parameters.blank?, description: "parameters cannot be blank" },
    ]

    skill_validation_blank_rules.each do |rule|
      if rule[:invalid]
        errors.add(:skill, rule[:description])
      end
    end

    # if any fields are empty, we can skip the rest of the validation
    if errors.size > 0
      return
    end

    skill_validation_rules = [
      { invalid: skill.name.length > 50, description: "name cannot be longer than 50 characters" },
      { invalid: !skill.name.match?("^[a-zA-Z0-9_-]+$"), description: "name must only contain a-z, A-Z, 0-9, underscores, or dashes" },
      { invalid: skill.description.length > 300, description: "description cannot be longer than 300 characters" },
      { invalid: skill.parameters.to_json.length > 1000, description: "parameters cannot be longer than 1000 characters and currently has " + skill.parameters.to_json.length.to_s + " characters" },
    ]

    skill_validation_rules.each do |rule|
      if rule[:invalid]
        errors.add(:skill, rule[:description])
      end
    end

    url_string_is_valid?(skill.url)

    top_parameters_are_valid(skill.parameters)

  end

  def oidc_settings_are_valid
    url_string_is_valid?(token_exchange_url)

    if third_party_token_header_key.blank?
      errors.add(:third_party_token_header_key, "OIDC config must contain a third party token header key")
    end

    if third_party_token_header_value.blank?
      errors.add(:third_party_token_header_value, "OIDC config must contain a third party token header value")
    end
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

  def top_parameters_are_valid(parameters)
    if parameters.blank?
      errors.add(:skill, "parameters cannot be blank")
      return
    end

    begin
      p = JSON.parse(parameters)
    rescue JSON::ParserError
      errors.add(:skill, "parameters must be valid JSON")
      return
    end

    if !p.is_a?(Hash)
      errors.add(:skill, "parameters must be a JSON object")
      return
    end

    if !p.key?("type") || p["type"] != "object"
      errors.add(:skill, "top level parameters type must be an object")
      return
    end

    parameters_are_valid(p)
  end

  def parameters_are_valid(parameters)
    if !parameters.is_a?(Hash)
      errors.add(:skill, "JSON schema definition must be a JSON object")
      return
    end

    if !parameters.key?("type")
      errors.add(:skill, "JSON schema definition must have a type")
      return
    end

    if !parameters["type"].is_a?(String)
      errors.add(:skill, "property definition type must be a string")
      return
    end

    if parameters["type"] != "object" && parameters["type"] != "number" && parameters["type"] != "string" && parameters["type"] != "boolean" && parameters["type"] != "array" && parameters["type"] != "integer" && parameters["type"] != "null"
      errors.add(:skill, "property definition type must be either 'object', 'number', 'string', 'boolean', 'array', 'null', or 'integer'")
      return
    end

    if parameters.key?("enum") && !parameters["enum"].is_a?(Array)
      errors.add(:skill, "property definition enum must be an array")
      return
    end

    if parameters.key?("required") && !parameters["required"].is_a?(Array)
      errors.add(:skill, "property definition enum must be an array")
      return
    end

    if parameters.key?("properties")
      if !parameters["properties"].is_a?(Hash)
        errors.add(:skill, "JSON schema properties must be a mapping of parameter names to parameter definitions")
        return
      end

      if parameters["properties"].size > 5
        errors.add(:skill, "parameters cannot have more than 5 properties")
        return
      end

      parameters["properties"].each do |_key, value|
        parameters_are_valid(value)
        if errors.size > 0
          return
        end
      end
      if errors.size > 0
        return
      end
    end

    if parameters.key?("items")
      parameters_are_valid(parameters["items"])
      if errors.size > 0
        return # rubocop:disable Style/RedundantReturn
      end
    end

  end

  def description_is_valid
    self.errors.add :description, "Config must contain a description" if self.description.nil?
  end

  def update_integration_copilot_status
    case app_type
    when "agent"
      integration.enable_copilot_listing!
    when "disabled"
      integration.disable_copilot_listing!
    end
  end
end
