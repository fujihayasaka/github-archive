# typed: false
# frozen_string_literal: true

module Configurable
  module MembersCanChangeProjectVisibility
    KEY = "allow_members_to_change_project_visibility"

    # Whether or not ordinary org members (as opposed to org admins) can change
    # the visibility of an organization-owned project. This defaults to false.
    #
    # Returns a Boolean.
    def members_can_change_project_visibility?
      config.enabled?(KEY)
    end

    # Allows ordinary org members (as opposed to org admins) to change the
    # visibility of organization-owned projects.
    #
    # actor - User making the change
    # force - Boolean which forces the setting to override any child objects. This
    #         defaults to `false`, but can be called with `true` when the receiver
    #         of this method is a Business (which makes it so the business's
    #         configuration to all of its Organizations).
    #
    # Returns nil.
    def allow_members_to_change_project_visibility(actor:, force: false)
      changed = config.enable!(KEY, actor, force)
      return unless changed

      GitHub.dogstats.increment("members_can_change_project_visibility.#{self.class.name.underscore}_settings.enable")
      GitHub.instrument("members_can_change_project_visibility.enable", instrumentation_payload(actor))

      nil
    end

    # Restricts the ability to change the visibility of an organization-owned
    # project to org admins.
    #
    # actor - User making the change
    # force - Boolean which forces the setting to override any child objects. This
    #         defaults to `false`, but can be called with `true` when the receiver
    #         of this method is a Business (which makes it so the business's
    #         configuration to all of its Organizations).
    #
    # Returns nil.
    def block_members_from_changing_project_visibility(actor:, force: false)
      changed = force ? config.disable!(KEY, actor, force) : config.delete(KEY, actor)
      return unless changed

      GitHub.dogstats.increment("members_can_change_project_visibility.#{self.class.name.underscore}_settings.disable")
      GitHub.instrument("members_can_change_project_visibility.disable", instrumentation_payload(actor))

      nil
    end

    # Clears the setting for whether or not ordinary org members can change
    # the visibility of a project. This restores the default of false for
    # that setting (meaning that only org admins can change the visibility
    # of a project).
    #
    # actor: User making the change
    #
    # Returns nil.
    def clear_members_can_change_project_visibility_setting(actor:)
      changed = config.delete(KEY, actor)
      return unless changed

      GitHub.dogstats.increment("members_can_change_project_visibility.#{self.class.name.underscore}_settings.clear")
      GitHub.instrument("members_can_change_project_visibility.clear", instrumentation_payload(actor))

      nil
    end

    # Whether or not this setting is enforced by a policy.
    #
    # Returns a Boolean.
    def members_can_change_project_visibility_policy?
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
  end
end
