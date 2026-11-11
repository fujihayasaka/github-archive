# typed: true
# frozen_string_literal: true

module Configurable
  module DisableRepositoryMemexProjects
    extend T::Helpers
    extend Configurable::Async

    requires_ancestor { Configurable }
    requires_ancestor { Object }

    KEY = "memex_projects.disable".freeze

    async_configurable :repository_memex_projects_enabled?
    def repository_memex_projects_enabled?
      !config.enabled?(KEY)
    end

    # Disables memex_projects at the repository level by setting a value of Configurable::TRUE
    # for Configurable::DisableRepositoryMemexProjects::KEY
    #
    # force: forces the setting to override any child objects
    # actor: the user making the change
    #
    # returns: nothing
    def disable_repository_memex_projects(actor:, force: false)
      changed = config.enable!(KEY, actor, force)
      return unless changed

      class_name = self.class.name&.underscore || "unknown"
      GitHub.dogstats.increment("repository_memex_projects.#{class_name}_settings.disable")
      GitHub.instrument(
        "repository_projects_change.disable",
        instrumentation_payload_for_memex_projects(actor))
    end

    # Enables memex_projects at the repository level by enabling a Configurable value of `false`
    # for Configurable::DisableRepositoryMemexProjects::KEY. Sets a value of Configurable::FALSE
    # when force is true. When force is false, the value will be deleted.
    #
    # force: forces the setting to override any child objects
    # actor: the user making the change
    #
    # returns: nothing
    def enable_repository_memex_projects(actor:, force: false)
      changed = if force
        config.disable!(KEY, actor, force)
      else
        config.delete(KEY, actor)
      end

      return unless changed

      class_name = self.class.name&.underscore || "unknown"
      GitHub.dogstats.increment("repository_memex_projects.#{class_name}_settings.enable")
      GitHub.instrument(
        "repository_projects_change.enable",
        instrumentation_payload_for_memex_projects(actor))
    end

    # Clears the setting of the repository projects policy by removing the value entirely
    # for Configurable::DisableRepositoryProjects::KEY
    #
    # actor: the user making the change
    #
    # returns: nothing
    def clear_repository_memex_projects_setting(actor:)
      changed = config.delete(KEY, actor)
      return unless changed

      class_name = self.class.name&.underscore || "unknown"
      GitHub.dogstats.increment("repository_projects.#{class_name}_settings.clear")
      GitHub.instrument(
        "repository_memex_projects_change.clear",
        instrumentation_payload_for_memex_projects(actor))
    end

    def update_repository_memex_projects_setting
      @modifying_user ||= User.find_by(id: GitHub.context[:actor_id])

      case @has_repository_memex_projects
      when true
        enable_repository_memex_projects(actor: @modifying_user)
      when false # take no action for nil
        disable_repository_memex_projects(actor: @modifying_user)
      end
    end

    def repository_memex_projects_setting_changed?
      return false if @has_repository_memex_projects.nil?

      @has_repository_memex_projects != repository_memex_projects_enabled?
    end

    private def instrumentation_payload_for_memex_projects(actor)
      payload = { user: actor, classic: false }

      if self.is_a?(Repository)
        payload[:repo] = self
      end

      # Using T.unsafe here because we are not currently ensuring that wherever this module is used
      # will define an owner method.
      owner = T.unsafe(self).owner
      if owner.is_a?(Organization)
        payload[:org] = owner
      end

      payload
    end
  end
end
