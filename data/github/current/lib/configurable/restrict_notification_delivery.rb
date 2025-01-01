# typed: true
# frozen_string_literal: true

module Configurable
  module RestrictNotificationDelivery
    extend Configurable::Async
    extend T::Helpers
    requires_ancestor { Kernel }
    requires_ancestor { Configurable }

    KEY = "restrict_notification_delivery"

    # Raised when the owner has a plan that does not support notification
    # restrictions
    class PlanUnsupportedError < StandardError; end

    # Raised when the owner is an enterprise-owned org and notification
    # restrictions are set on the owning enterprise
    class AlreadySetOnEnterpriseError < StandardError; end

    # Raised when the owner has no verified domains
    class NoVerifiedDomainsError < StandardError; end

    # Raised when SMTP is not configured in the environment
    class SmtpNotConfiguredError < StandardError; end

    # Public: Are notification restrictions enabled on the object?
    #
    # Returns Boolean
    async_configurable :restrict_notifications_to_verified_domains?
    def restrict_notifications_to_verified_domains?
      config.enabled?(KEY)
    end

    # Public: Are notification restrictions enabled on the object or at a
    # higher level object?
    #
    # For example, currently returns true when called on an org that is a member
    # of a business that has notification restrictions enabled.
    #
    # Returns Boolean.
    def restrict_notifications_to_verified_domains_policy?
      restrict_notifications_to_verified_domains? && config.inherited?(KEY)
    end

    # Public: Enables restricting notifications to emails that match a verified
    # domain for an organization or enterprise.
    #
    # actor - The User enabling this setting.
    # force - the force param to pass to the Configurable call. Creates a policy if true.
    # notify_members - do we need to send an email to members who will no longer receive
    #                  notifications that restrictions have been enabled? (true by default)
    #
    # Returns a Boolean.
    def enable_notification_restrictions(actor:, force: false, notify_members: true)
      if T.unsafe(self).respond_to?(:plan_supports?) && !T.unsafe(self).plan_supports?(:restrict_notification_delivery)
        raise PlanUnsupportedError.new "Notification restrictions are not supported on the owner's plan."
      end

      if self.is_a?(Organization) && self.restrict_notifications_to_verified_domains_policy?
        raise AlreadySetOnEnterpriseError.new enforcement_already_enabled_message
      end

      unless VerifiableDomain.usable_for(self).verified_or_approved.any?
        raise NoVerifiedDomainsError.new "You must have at least one verified or approved domain to configure notification restrictions."
      end

      unless GitHub.smtp_enabled?
        raise SmtpNotConfiguredError.new "SMTP must be configured to enable email-based notification restrictions."
      end

      return true if restrict_notifications_to_verified_domains?

      changed = config.enable!(KEY, actor, force)
      return false unless changed

      GitHub.dogstats.increment("restrict_notification_delivery.enable")
      GitHub.instrument("restrict_notification_delivery.enable", audit_context(actor))

      # notify members who do not have a verified domain email and can no longer
      # receive notifications for this organization or business
      # The job will also trigger a hydro event for notification restrictions getting enabled
      NotifyNotificationRestrictedMembersJob.perform_later(
        self, actor: actor, notify_members: notify_members
      )

      # automatically set eligible email address for newsies routing for affected members
      UpdateOrganizationRoutingToEligibleEmailJob.perform_later(self)

      true
    end

    # Public: Disables restricting notifications to emails that match a verified
    # domain for an organization or enterprise.
    #
    # actor - The User enabling this setting.
    #
    # Returns a Boolean.
    def disable_notification_restrictions(actor:, force: false)
      if self.is_a?(Organization) && self.restrict_notifications_to_verified_domains_policy?
        raise AlreadySetOnEnterpriseError.new enforcement_already_enabled_message
      end

      return true if !restrict_notifications_to_verified_domains? && !force

      changed = if force
        config.disable!(KEY, actor, force)
      else
        config.delete(KEY, actor)
      end
      return false unless changed

      GitHub.dogstats.increment("restrict_notification_delivery.disable")
      GitHub.instrument("restrict_notification_delivery.disable", audit_context(actor))
      GlobalInstrumenter.instrument("verifiable_domains.notification_restrictions_disabled", {
        owner: self,
        actor: actor
      })
      true
    end

    private

    def audit_context(actor)
      payload = {
        actor: actor,
        owner: self,
      }
      if self.is_a?(Organization) && business.present?
        payload[:business_id] = business&.id
      end

      T.unsafe(self).event_context.merge(payload)
    end

    def enforcement_already_enabled_message
      "The enterprise has already restricted notifications to only verified and approved domain email addresses."
    end
  end
end
