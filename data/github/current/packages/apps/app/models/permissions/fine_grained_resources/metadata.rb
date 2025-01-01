# typed: true
# frozen_string_literal: true

module Permissions::FineGrainedResources
  class Metadata
    APPS_REST_PERMISSIONS_BASE_URL = "#{GitHub.developer_help_url}/rest/overview/permissions-required-for-github-apps".freeze
    APPS_ENTERPRISE_REST_PERMISSIONS_BASE_URL = "#{GitHub.help_url(ghec_exclusive: true)}/rest/overview/permissions-required-for-github-apps".freeze
    PATSV2_REST_PERMISSIONS_BASE_URL = "#{GitHub.developer_help_url}/rest/overview/permissions-required-for-fine-grained-personal-access-tokens".freeze

    def self.actions
      return @fine_grained_actions unless @fine_grained_actions.nil?

      fine_grained_actions_config = YAML.safe_load Rails.root.join("config/access_control/fine_grained_permissions/programmatic_actor_fine_grained_resource_actions.yml").read

      @fine_grained_actions = fine_grained_actions_config.symbolize_keys
    end

    def self.action_description(action)
      actions.fetch(action, "No access")
    end

    def self.description(resource)
      return "" unless GitHub.fine_grained_resource(resource).present?
      GitHub.fine_grained_resource(resource).fetch("description", "")
    end

    def self.base_docs_url(resource, actor)
      return PATSV2_REST_PERMISSIONS_BASE_URL if actor&.is_a? UserProgrammaticAccess
      return APPS_ENTERPRISE_REST_PERMISSIONS_BASE_URL if resource_group(resource) == "business"

      APPS_REST_PERMISSIONS_BASE_URL
    end

    def self.resource_anchor(resource, actor)
      return "" unless GitHub.fine_grained_resource(resource).present?
      group = GitHub.fine_grained_resource(resource).fetch("resource_group", "")
      return "" if group.blank?

      group_name = group == "business" ? "enterprise" : group

      title = GitHub.fine_grained_resource(resource).fetch("title", "").parameterize
      ["#", group_name, "-permissions-for-", title].join
    end

    def self.docs_url(resource, actor = nil)
      base_docs_url(resource, actor) + resource_anchor(resource, actor)
    end

    def self.fgp(resource)
      return [] unless GitHub.fine_grained_resource(resource).present?

      highest = GitHub.fine_grained_resource(resource).fetch("fgp", nil)
      return [] unless highest

      actions_map = { read_only: ["Read-only"], write_only: ["Read and write"], read_write: ["Read-only", "Read and write"], adminable: ["Read-only", "Read and write", "Admin"] }
      actions_map[highest.to_sym] || []
    end

    def self.title(resource)
      return "" unless GitHub.fine_grained_resource(resource).present?
      GitHub.fine_grained_resource(resource).fetch("title", "")
    end

    def self.human_name(resource)
      return "" unless GitHub.fine_grained_resource(resource).present?
      GitHub.fine_grained_resource(resource).fetch("human_name", "")
    end

    def self.resource_group(resource)
      return "" unless GitHub.fine_grained_resource(resource).present?
      GitHub.fine_grained_resource(resource).fetch("resource_group", "")
    end

    # Override which name should be used as reference to some resources
    def self.human_readable_resource_names
      return @human_readable_resources if defined?(@human_readable_resources)

      {}.tap do |resources|
        Business::Resources.subject_types.each do |resource|
          resources[resource] = human_name(resource)
        end

        Repository::Resources.subject_types.each do |resource|
          resources[resource] = human_name(resource)
        end

        Organization::Resources.subject_types.each do |resource|
          resources[resource] = human_name(resource)
        end

        User::Resources.subject_types.each do |resource|
          resources[resource] = human_name(resource)
        end

        @human_readable_resources = resources
      end
    end

    def initialize(resource, actor = nil)
      @resource = resource
      @actor = actor
    end

    def description
      self.class.description(@resource)
    end

    def docs_url
      self.class.docs_url(@resource, @actor)
    end

    def fgp
      self.class.fgp(@resource)
    end

    def title
      self.class.title(@resource)
    end

    def human_name
      self.class.human_name(@resource)
    end

    def resource_group
      self.class.resource_anchor(@resource, @actor)
    end

    def to_h
      {
        actions: self.class.actions,
        description:,
        docs_url:,
        fgp:,
        human_name:,
        resource_group:,
        title:,
      }
    end
  end
end
