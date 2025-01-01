# typed: true
# frozen_string_literal: true

class OrgFgpMetadata
  attr_reader :label, :category, :description

  # Fine Grained Permission metadata
  def initialize(fgp)
    @label = fgp
    @category = OrgFgpMetadata.category_for(fgp)
    @description = OrgFgpMetadata.description_for(fgp)
  end

  # FGP contains the metadata for an individual fine grained permission
  def self.for(fgp)
    new(fgp.to_sym)
  end

  # Public: get all the categories and FGPs for a role
  #
  # - role: the Role object
  #
  # Returns a Hash of categories titles to FGP descriptions
  def self.for_role(role)
    perms = role.permissions.map(&:action)

    CATEGORIES.each_with_object(Hash.new { |h, k| h[k] = [] }) do |(category, permissions), result|
      permissions.each do |category_permission|
        if perms.include?(category_permission.to_s)
          result[title_for(category)] << description_for(category_permission)
        end
      end
    end
  end

  def self.categories
    CATEGORIES.keys
  end

  def self.category_for(fgp)
    CATEGORIES.each do |category, fgps|
      return category if fgps.include?(fgp)
    end

    :unknown
  end

  def self.description_for(fgp)
    DESCRIPTIONS[fgp] || "unknown"
  end

  # Public: the human readable title for every FGP category
  def self.title_for(category)
    case category
    when :access_management
      "Access management"
    when :automation
      "Apps and automation"
    when :general
      "General"
    when :repository
      "Repository"
    when :security
      "Security"
    when :ci_cd
      "CI/CD"
    end
  end

  # Public: the octicon for every FGP category
  def self.icon_for(category)
    case category
    when :access_management
      "unlock"
    when :automation
      "hubot"
    when :general
      "gear"
    when :repository
      "repo"
    when :security
      "shield"
    when :ci_cd
      "workflow"
    end
  end

  # Public: the octicon for every FGP category by title
  # hard coded for now
  def self.icon_for_title(title)
    case title
    when "Access management"
      "unlock"
    when "Apps and automation"
      "hubot"
    when "General"
      "gear"
    when "Repository"
      "repo"
    when "Security"
      "shield"
    when "CI/CD"
      "workflow"
    end
  end

  DESCRIPTIONS = {
    write_organization_custom_org_role: "Manage custom organization roles",
    read_organization_custom_org_role: "View organization roles",
    write_organization_custom_repo_role: "Manage custom repository roles",
    read_organization_custom_repo_role: "View custom repository roles",
    read_audit_logs: "View organization audit log",
    manage_organization_webhooks: "Manage organization webhooks",
    manage_organization_oauth_application_policy: "Manage organization OAuth application policies",
    manage_organization_actions_self_hosted_runners: "Manage organization actions self-hosted runners",
    manage_organization_ref_rules: "Manage organization ref update rules and rulesets",
    manage_org_custom_properties_definitions: "Manage the organization's custom properties definitions",
    edit_org_custom_properties_values: "Edit custom properties values at the organization level",
    write_organization_actions_settings: "Manage organization Actions policies",
    write_organization_actions_secrets: "Manage organization Actions secrets",
    write_organization_actions_variables: "Manage organization Actions variables",
    write_organization_runners_and_runner_groups: "Manage organization runners and runner groups",
    write_organization_packages: "Manage organization packages policies",
    read_organization_actions_usage_metrics: "View organization Actions usage metrics",
    read_organization_network_configurations: "View organization hosted compute network configurations",
    write_organization_network_configurations: "Edit organization hosted compute network configurations",
    org_review_and_manage_secret_scanning_bypass_requests: "Review and manage secret scanning bypass requests",
    view_org_api_insights: "View organization API Insights Dashboard",
  }

  CATEGORIES = {
    general: %i[
      manage_org_custom_properties_definitions
      edit_org_custom_properties_values
      view_org_api_insights
    ],
    access_management: %i[
      read_organization_custom_org_role
      write_organization_custom_org_role
      read_organization_custom_repo_role
      write_organization_custom_repo_role
    ],
    security: %i[
      read_audit_logs
      org_review_and_manage_secret_scanning_bypass_requests
    ],
    automation: %i[
      manage_organization_webhooks
      manage_organization_oauth_application_policy
      manage_organization_actions_self_hosted_runners
    ],
    repository: %i[
      manage_organization_ref_rules
    ],
    ci_cd: %i[
      write_organization_actions_settings
      write_organization_actions_secrets
      write_organization_actions_variables
      write_organization_runners_and_runner_groups
      write_organization_packages
      read_organization_actions_usage_metrics
      read_organization_network_configurations
      write_organization_network_configurations
    ],
  }
end
