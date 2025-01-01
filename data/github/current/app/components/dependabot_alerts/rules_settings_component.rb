# typed: true
# frozen_string_literal: true

class DependabotAlerts::RulesSettingsComponent < ApplicationComponent
  attr_reader :repository, :organization, :component_view

  def initialize(repository: nil, organization: nil)
    @repository = repository
    @organization = organization

    if @repository
      @component_view = "repository"
    elsif @organization
      @component_view = "organization"
    end
  end

  def tagline
    case component_view
    when "repository"
      if repository.dependabot_custom_rules_writable?
        "Create your own custom rules and manage alert presets."
      else
        "Review and manage alert presets."
      end
    when "organization"
      "Create your own custom rules and manage alert presets."
    end
  end

  def path_to_configure_rules
    case component_view
    when "repository"
      dependabot_rules_path
    when "organization"
      settings_org_dependabot_rules_path(organization_id: @organization.display_login)
    end
  end

  def rule_count
    case component_view
    when "repository"
      @repository.enabled_dependabot_rules_count
    when "organization"
      @organization.enabled_dependabot_rules_count
    end
  end

  def rules_enabled
    pluralize(rule_count, "rule") + " enabled"
  end
end
