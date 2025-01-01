# typed: false
# frozen_string_literal: true

module Configurable
  module DisableUserProjects
    extend Configurable::Async
    KEY = "user_projects.disable".freeze

    async_configurable :user_projects_enabled?
    def user_projects_enabled?
      return false if basic_seats_plan_business?
      !config.enabled?(KEY)
    end

    # Disables projects for users belonging to an Enterprise business by creating a Configurable value of `true`
    # for Configurable::DisableUserProjects::KEY
    #
    # force: forces the setting to override any child objects
    # actor: the user making the change
    #
    # returns: nothing
    def disable_user_projects(actor:, force: false)
      return if basic_seats_plan_business?
      changed = config.enable!(KEY, actor, force)
      return unless changed

      GitHub.dogstats.increment("user_projects.#{self.class.name.underscore}_settings.disable")
      GitHub.instrument(
        "user_projects_change.disable",
        instrumentation_payload(actor))

    end

    # Enables projects for users belonging to an Enterprise business by enabling a Configurable value of `false`
    # for Configurable::DisableOrganizationProjects::KEY
    #
    # force: forces the setting to override any child objects
    # actor: the user making the change
    #
    # returns: nothing
    def enable_user_projects(actor:, force: false)
      return if basic_seats_plan_business?
      changed = if force
        config.disable!(KEY, actor, force)
      else
        config.delete(KEY, actor)
      end

      return unless changed

      GitHub.dogstats.increment("user_projects.#{self.class.name.underscore}_settings.enable")
      GitHub.instrument(
        "user_projects_change.enable",
        instrumentation_payload(actor))
    end

    private def basic_seats_plan_business?
      if self.is_a?(Business)
        T.bind(self, Business)
        return true if self.seats_plan_basic?
      end
      false
    end

    # Returns: hash of parameters for instrumentation
    private def instrumentation_payload(actor)
      payload = { user: actor }

      if self.is_a?(Business)
        payload[:business] = self
      end

      payload
    end
  end
end
