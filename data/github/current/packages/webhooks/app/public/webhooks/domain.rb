# typed: strict
# frozen_string_literal: true

module Webhooks
  class Domain < GH::Domain::Base
    extend T::Sig

    include Repositories::Domain::Provider

    # If we want to be nice, we bump this up from the default of 20 in dotcom
    INCREASED_HOOK_LIMIT = 30

    # Are push notifications active for this repository?
    sig { params(repository_id: Integer).returns(T::Boolean) }
    def push_notifications_active?(repository_id:)
      T.unsafe(repository_email_scope(repository_id)).active.exists?
    end

    # Sends a fake webhook for user testing purposes
    sig { params(hook: IHook).void.checked(:always).on_failure(:raise) }
    def send_test_webhook(hook:) # rubocop:todo Metrics/MethodLength
      repository = T.cast(hook.installation_target, Repositories::IRepository)
      last_push = repositories_domain.pushes.latest_for_repo(repository_id: T.must(repository.id))

      return unless last_push

      payload = {
        target_hook: hook,
        repo: T.cast(repository, Repository), # rubocop:todo GitHub/AvoidCast
        pusher: last_push.pusher,
        ref: last_push.ref,
        before: last_push.before,
        after: last_push.after,
        triggered_at: Time.now,
      }
      event = Hook::Event::PushEvent.new(payload)
      delivery_system = Hook::DeliverySystem.new(event)

      delivery_system.generate_push_event_hookshot_payloads
      delivery_system.deliver_push_event_later
    end

    # Returns the rate limit for the given webhook
    sig { params(hook: IHook).returns(T.nilable(Integer)).checked(:always).on_failure(:raise) }
    def hook_limit(hook)
      return nil unless hook.repo_hook?
      repository = T.cast(hook.installation_target, Repositories::IRepository)

      INCREASED_HOOK_LIMIT if (
        repository.feature_enabled?(:increased_webhook_limit, memoize: false) ||
        repository.owner&.feature_enabled?(:increased_webhook_limit, memoize: false)
      )
    end

    private

    sig { params(repository_id: Integer).returns(ActiveRecord::Relation) }
    def repository_scope(repository_id)
      Hook.where(
        installation_target_id: repository_id,
        installation_target_type: "Repository",
      )
    end

    sig { params(repository_id: Integer).returns(ActiveRecord::Relation) }
    def repository_email_scope(repository_id)
      repository_scope(repository_id).where("hooks.name" => "email")
    end
  end
end
