# typed: true
# frozen_string_literal: true

module Permissions::FineGrainedResources
  class Metadata
    APPS_REST_PERMISSIONS_BASE_URL = "#{GitHub.developer_help_url}/rest/overview/permissions-required-for-github-apps".freeze
    PATSV2_REST_PERMISSIONS_BASE_URL = "#{GitHub.developer_help_url}/rest/overview/permissions-required-for-fine-grained-personal-access-tokens".freeze

    def self.actions
      I18n.t("programmatic_actor_fine_grained_resource_actions")
    end

    def self.action_description(action)
      I18n.t("programmatic_actor_fine_grained_resource_actions.#{action}", default: "No access")
    end

    def self.description(resource)
      I18n.t("programmatic_actor_fine_grained_resources.#{resource}.description", default: "")
    end

    def self.base_docs_url(actor)
      return PATSV2_REST_PERMISSIONS_BASE_URL if actor&.is_a? UserProgrammaticAccess

      APPS_REST_PERMISSIONS_BASE_URL
    end

    def self.resource_anchor(resource, actor)
      group = I18n.t("programmatic_actor_fine_grained_resources.#{resource}.resource_group", default: "", locale: :en)
      return "" if group.empty?

      title = I18n.t("programmatic_actor_fine_grained_resources.#{resource}.title", default: "", locale: :en).parameterize
      ["#", group, "-permissions-for-", title].join
    end

    def self.docs_url(resource, actor = nil)
      base_docs_url(actor) + resource_anchor(resource, actor)
    end

    def self.title(resource)
      I18n.t("programmatic_actor_fine_grained_resources.#{resource}.title", default: "")
    end

    def self.human_name(resource)
      I18n.t("programmatic_actor_fine_grained_resources.#{resource}.human_name", default: "")
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

    def title
      self.class.title(@resource)
    end
  end
end
