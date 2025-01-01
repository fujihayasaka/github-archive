# typed: true
# frozen_string_literal: true

class HydroNotificationsOnPushJob < Repositories::PushHydroMessageJob
  include Webhooks::Domain::Provider

  queue_as :hydro_notifications_on_push

  def perform
    ref_updates.each do |ref_update|
      push_notifications_active = if repository.repo_hook_associations_ff?
        webhooks_domain.push_notifications_active?(repository_id: T.must(repository.id))
      else
        repository.push_notifications_active?
      end

      if push_notifications_active
        job_class = DeliverRepositoryPushNotificationJob

        # We wait 10 seconds to give async spam checks time to finish https://github.com/github/notifications/issues/296
        if GitHub::SpamChecker.external_spamminess_check_enabled?
          job_class = job_class.set(wait: GitHub::SpamChecker::DELAY_FOR_EXTERNAL_CHECKS)
        end

        job_class.perform_later(
          repository_id: repository.id,
          ref: ref_update.ref,
          before: ref_update.before,
          after: ref_update.after,
          pusher_id: pusher.id,
        )
      end
    end
  end
end
