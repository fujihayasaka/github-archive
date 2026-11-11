# typed: false
# frozen_string_literal: true

module Configurable
  module DisableOrganizationProjects
    extend Configurable::Async

    KEY = "organization_projects.disable".freeze

    async_configurable :organization_projects_enabled?
    def organization_projects_enabled?
      return false if basic_seats_plan_business_without_organization_projects?
      !config.enabled?(KEY)
    end

    # Disables projects at the organization level by creating a Configurable value of `true`
    # for Configurable::DisableOrganizationProjects::KEY
    #
    # force: forces the setting to override any child objects
    # actor: the user making the change
    #
    # returns: nothing
    def disable_organization_projects(actor:, force: false)
      return if basic_seats_plan_business_without_organization_projects?
      changed = config.enable!(KEY, actor, force)
      return unless changed

      GitHub.dogstats.increment("organization_projects.#{self.class.name.underscore}_settings.disable")
      GitHub.instrument(
        "organization_projects_change.disable",
        instrumentation_payload(actor))
    end

    # Enables projects at the organization level by enabling a Configurable value of `false`
    # for Configurable::DisableOrganizationProjects::KEY
    #
    # force: forces the setting to override any child objects
    # actor: the user making the change
    #
    # returns: nothing
    def enable_organization_projects(actor:, force: false)
      return if basic_seats_plan_business_without_organization_projects?
      changed = if force
        config.disable!(KEY, actor, force)
      else
        config.delete(KEY, actor)
      end

      return unless changed

      GitHub.dogstats.increment("organization_projects.#{self.class.name.underscore}_settings.enable")
      GitHub.instrument(
        "organization_projects_change.enable",
        instrumentation_payload(actor))
    end

    # Clears the setting of an organization's projects policy by removing the value entirely
    # for Configurable::DisableOrganizationProjects::KEY
    #
    # actor: the user making the change
    #
    # returns: nothing
    def clear_organization_projects_setting(actor:)
      changed = config.delete(KEY, actor)
      return unless changed

      GitHub.dogstats.increment("organization_projects.#{self.class.name.underscore}_settings.clear")
      GitHub.instrument(
        "organization_projects_change.clear",
        instrumentation_payload(actor))
    end

    def update_organization_projects_setting
      @modifying_user ||= User.find_by_id(GitHub.context[:actor_id])

      case @has_organization_projects
      when true
        enable_organization_projects(actor: @modifying_user)
      when false # take no action for nil
        disable_organization_projects(actor: @modifying_user)
      end
    end

    def organization_projects_setting_changed?
      return false if @has_organization_projects.nil?

      @has_organization_projects != organization_projects_enabled?
    end

    # is there a policy enabling/disabling organization projects?
    def organization_projects_policy?
      !!config.final?(KEY)
    end

    private def instrumentation_payload(actor)
      payload = { user: actor }

      if self.is_a?(Organization)
        payload[:org] = self
        payload[:business] = self.business if self.business
      elsif self.is_a?(Business)
        payload[:business] = self
      end

      payload
    end

    private def basic_seats_plan_business_without_organization_projects?
      if self.is_a?(Organization)
        T.bind(self, Organization)
        return true if self.async_business&.sync&.seats_plan_basic?
      elsif self.is_a?(Business)
        T.bind(self, Business)
        return true if self.seats_plan_basic?
      end
      false
    end
  end
end
