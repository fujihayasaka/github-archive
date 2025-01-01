# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

module Reminders
  class TriggerMergeableUpdateJob < RealTimeJob
    resolve_tenant_context do |kwargs|
      repository = Repositories::Public.find_active(kwargs[:repo_id])
      if repository
        Business.find_by(id: repository.tenant_id)
      end
    end

    def self.delay
      if FeatureFlag.vexi.enabled?(:reminders_with_increased_delay, default: true)
        Rails.env.development? ? 0 : 60.minutes
      else
        Rails.env.development? ? 0 : 15.minutes
      end
    end

    def self.perform_later_with_delay(*args)
      args = args.first
      if delay.zero?
        perform_later(**args)
      else
        set(wait: delay).perform_later(**args)
      end
    end

    locked_by timeout: 30.minutes, key: -> (job) { job.build_lock_key }

    def perform(push_id:, ref:, repo_id:, event_at:, transaction_id:)
      repository = Repositories::Public.find_active(repo_id)
      return unless repository
      return if FeatureFlag.vexi.enabled?(:disable_reminders_update_job, repository, default: false)
      # If merge conflict reminder is sunset, we don't want to run the job.
      return if FeatureFlag.vexi.enabled?(:merge_conflicts_reminder_sunset, repository.owner, default: false)

      ref_name = ref.to_s.sub(%r{\Arefs/(?:heads|tags)/}, "")

      user_ids = PersonalReminder.listener_ids_for(repository.owner, event_type: :merge_conflict)

      if user_ids.present?
        pull_requests = PullRequest.open_based_on_ref(repository, ref_name).where(user_id: user_ids)

        pull_requests.each_slice(10) do |batch| # domain-isolation-query-violation:ignore:packages/issues (SELECT)
          batch.each do |pull_request|
            pull_request.enqueue_mergeable_update(priority: :low)
          end

          sleep(5)
        end

        GitHub.logger.info("Update mergeable pull-requests", {
          "code.namespace" => self.class.name,
          "gh.job.active_job_id" => job_id,
          "gh.spokes.spec" => repository.dgit_spec,
          "gh.scheduled_reminders.pull_requests_updates.count" => pull_requests.size
        })
      end
    end

    def build_lock_key
      [
        arguments.first[:ref],
        arguments.first[:repo_id],
      ].join("-")
    end
  end
end
