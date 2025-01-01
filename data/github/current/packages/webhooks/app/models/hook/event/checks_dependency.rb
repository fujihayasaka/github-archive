# typed: true
# frozen_string_literal: true

class Hook::Event
  module ChecksDependency
    extend T::Helpers

    def actor
      return @actor if defined?(@actor)
      @actor = if T.unsafe(self).actor_id
        User.find_by(id: T.unsafe(self).actor_id)
      else
        T.unsafe(self).check_suite&.safe_actor
      end
    end

    def app
      @app ||= T.unsafe(self).check_suite.github_app
    end

    def app_is_installed?
      app.installations.not_suspended.with_repository(target_repository).any?
    end

    def app_installation_ids
      return [] if app.suspended?

      app.installations.not_suspended.with_repository(target_repository).pluck(:id)
    end

    def app_is_subscribed?
      # check if the hook subscription for the request event exists
      HookEventSubscription.with_name_and_subscriber(T.unsafe(self).event_type, "IntegrationInstallation", app_installation_ids).any?
    end

    # Override subscribed_hooks to only include the specific app's hook.
    # Specified on a per action basis when the action is subscribed to.
    def subscribed_hooks
      # specific_app_only lets us send this hook to a specific app instead of any app subscribed to these events
      if T.unsafe(self).specific_app_only && app_is_installed?
        return @target_hook if defined?(@target_hook)
        @target_hook = []
        return @target_hook if app.suspended?

        observability_tags = []

        if GitHub.flipper[:checks_request_hook_when_permissions_and_subscription].enabled?(app)
          observability_tags << "flag:enabled"
          if app.subscribable_hook? && app_is_subscribed?
            @target_hook << app.hook
            observability_tags << "passes_gate:true"
          else
            observability_tags << "passes_gate:false"
          end
        else
          observability_tags << "flag:disabled"
          if app.subscribable_hook?
            @target_hook << app.hook
            observability_tags << "passes_gate:true"
          else
            observability_tags << "passes_gate:false"
          end
        end

        GitHub.dogstats.increment("checks.events.checks_request_hook_when_permissions_and_subscription", tags: observability_tags)

        @target_hook
      else
        super
      end
    end

    # Override subscribed_installations_for so that the installation
    # information is included in event payloads for these specific app
    # action payloads, where the app may not be subscribed to the event.
    def subscribed_installations_for(integration_id)
      # specific_app_only lets us send this hook to a specific app instead of any app subscribed to these events
      if T.unsafe(self).specific_app_only && app.id == integration_id.to_i
        app.installations.not_suspended.with_repository(target_repository)
      else
        super
      end
    end

    def target_repository
      @target_repository ||= T.unsafe(self).check_suite.try(:repository)
    end
  end
end
