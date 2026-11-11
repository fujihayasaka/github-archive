# typed: false
# frozen_string_literal: true

module Configurable
  module DisableRepositoryProjects
    extend Configurable::Async

    KEY = "projects.disable".freeze

    async_configurable :repository_projects_enabled?
    def repository_projects_enabled?
      return false if basic_seats_plan_business_without_repository_projects?
      !config.enabled?(KEY)
    end

    # Disables projects at the repository level by setting a value of Configurable::TRUE
    # for Configurable::DisableRepositoryProjects::KEY
    #
    # force: forces the setting to override any child objects
    # actor: the user making the change
    #
    # returns: nothing
    def disable_repository_projects(actor:, force: false)
      return if basic_seats_plan_business_without_repository_projects?
      changed = config.enable!(KEY, actor, force)
      return unless changed

      GitHub.dogstats.increment("repository_projects.#{self.class.name.underscore}_settings.disable")
      GitHub.instrument(
        "repository_projects_change.disable",
        instrumentation_payload_for_projects(actor))
    end

    # Enables projects at the repository level by enabling a Configurable value of `false`
    # for Configurable::DisableRepositoryProjects::KEY. Sets a value of Configurable::FALSE
    # when force is true. When force is false, the value will be deleted.
    #
    # force: forces the setting to override any child objects
    # actor: the user making the change
    #
    # returns: nothing
    def enable_repository_projects(actor:, force: false)
      return if basic_seats_plan_business_without_repository_projects?
      changed = if force
        config.disable!(KEY, actor, force)
      else
        config.delete(KEY, actor)
      end

      return unless changed

      GitHub.dogstats.increment("repository_projects.#{self.class.name.underscore}_settings.enable")
      GitHub.instrument(
        "repository_projects_change.enable",
        instrumentation_payload_for_projects(actor))
    end

    # Clears the setting of the repository projects policy by removing the value entirely
    # for Configurable::DisableRepositoryProjects::KEY
    #
    # actor: the user making the change
    #
    # returns: nothing
    def clear_repository_projects_setting(actor:)
      changed = config.delete(KEY, actor)
      return unless changed

      GitHub.dogstats.increment("repository_projects.#{self.class.name.underscore}_settings.clear")
      GitHub.instrument(
        "repository_projects_change.clear",
        instrumentation_payload_for_projects(actor))
    end

    def update_repository_projects_setting
      @modifying_user ||= User.find_by_id(GitHub.context[:actor_id])

      case @has_repository_projects
      when true
        enable_repository_projects(actor: @modifying_user)
      when false # take no action for nil
        disable_repository_projects(actor: @modifying_user)
      end
    end

    def repository_projects_setting_changed?
      return false if @has_repository_projects.nil?

      @has_repository_projects != repository_projects_enabled?
    end

    # is there a policy enabling/disabling repository projects?
    def repository_projects_policy?
      !!config.final?(KEY)
    end

    private def instrumentation_payload_for_projects(actor)
      payload = { user: actor, classic: true }

      if self.is_a?(Organization)
        payload[:org] = self
        payload[:business] = self.business if self.business
      elsif self.is_a?(Business)
        payload[:business] = self
      end

      payload
    end

    private def basic_seats_plan_business_without_repository_projects?
      if self.is_a?(Repository)
        T.bind(self, Repository)
        return true if self.async_organization&.sync&.async_business&.sync&.seats_plan_basic?
      elsif self.is_a?(Organization)
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
