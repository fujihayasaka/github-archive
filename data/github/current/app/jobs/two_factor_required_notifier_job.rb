# typed: true
# frozen_string_literal: true

class TwoFactorRequiredNotifierJob < ApplicationJob
  SCHEDULE_INTERVAL = 1.hour
  BATCH_SIZE = 500
  MAX_THROTTLE_RETRIES = 5

  queue_as :two_factor_required_notifier
  schedule interval: SCHEDULE_INTERVAL, condition: -> { !GitHub.enterprise? }

  LOCK_TIMEOUT = 60 * 60 * 2 # 2 hours
  TIME_LIMIT = 1.5.hours.in_seconds
  NOTIFY_LIMIT = 100_000

  # Don't run more than one of this job at a time
  locked_by timeout: LOCK_TIMEOUT, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC
  retry_on_dirty_exit

  def perform
    return if GitHub.single_or_multi_tenant_enterprise?
    return unless GitHub.flipper[:bulwark_two_factor_required_notifier_job].enabled?

    GitHub::SafeTimer.timeout(TIME_LIMIT) do |timer|
      perform_start = Time.now.utc

      queries = [
        # query for users that have never received an email notification and do NOT have 2FA enabled
        ["two_factor_required_notifier.initial", TwoFactorRequirementMetadata.method(:not_yet_notified), AccountMailer.method(:two_factor_requirement_initial_notification_2fa_disabled), AccountMailer.method(:two_factor_requirement_initial_notification_2fa_enabled)],
        # query for users that are ready for the first warning email notification and do NOT have 2FA enabled
        ["two_factor_required_notifier.warning.first", TwoFactorRequirementMetadata.method(:first_warning_not_sent), AccountMailer.method(:two_factor_requirement_warning)],
        # query for users that are ready for the second warning email notification and do NOT have 2FA enabled
        ["two_factor_required_notifier.warning.second", TwoFactorRequirementMetadata.method(:second_warning_not_sent), AccountMailer.method(:two_factor_requirement_warning)],
        # query for users that are ready for the third warning email notification and do NOT have 2FA enabled
        ["two_factor_required_notifier.warning.third", TwoFactorRequirementMetadata.method(:third_warning_not_sent), AccountMailer.method(:two_factor_requirement_warning)],
        # query for users that are ready for the final warning email notification and do NOT have 2FA enabled
        ["two_factor_required_notifier.warning.final", TwoFactorRequirementMetadata.method(:final_warning_not_sent), AccountMailer.method(:two_factor_requirement_warning)],
        # query for users that are ready for a final email notification and do NOT have 2FA enabled
        ["two_factor_required_notifier.final", TwoFactorRequirementMetadata.method(:final_notification_not_sent), AccountMailer.method(:two_factor_requirement_now_enforced)],
      ]

      total_count = 0

      (queries).each do |query_name, query, two_factor_disabled_mailer, two_factor_enabled_mailer|
        query_start = Time.now.utc

        break if total_count >= NOTIFY_LIMIT || timer.expired?

        batches_for(query, batch_size: BATCH_SIZE) do |batch|
          batch_start = Time.now.utc

          GitHub.dogstats.increment("#{query_name}.batch.count")
          GitHub.dogstats.histogram("#{query_name}.batch.size", batch.size)

          break if total_count >= NOTIFY_LIMIT || timer.expired?

          user_ids = batch.map(&:user_id)
          users = User.where(id: user_ids).index_by(&:id)
          two_factor_credententials = TwoFactorCredential.where(user_id: user_ids).index_by(&:user_id)

          batch.each do |metadata|
            if GitHub.flipper[:bulwark_two_factor_required_feature].enabled? && GitHub.flipper[:bulwark_two_factor_required_job_notifications].enabled?
              break if total_count >= NOTIFY_LIMIT || timer.expired?
              user = users[metadata.user_id]

              tags = ["deleted:#{user.deleted?}", "spammy:#{user.spammy?}", "suspended:#{user.suspended?}"]

              if user.deleted? || user.spammy? || user.suspended?
                GitHub.dogstats.increment("#{query_name}.skipped.count", tags: tags)
                next
              end

              notified = false
              two_factor_enabled = two_factor_credententials[metadata.user_id].present?
              if two_factor_disabled_mailer.present? && !two_factor_enabled
                two_factor_disabled_mailer.call(user).deliver_later
                notified = true
              elsif two_factor_enabled_mailer.present? && two_factor_enabled
                two_factor_enabled_mailer.call(user).deliver_later
                notified = true
              else
                tags << "two_factor_enabled:#{two_factor_enabled}"
                GitHub.dogstats.increment("#{query_name}.skipped.count", tags: tags)
                next
              end

              notified_count = metadata.email_notified_count + 1

              # sets last_email_notified_at to query_start to avoid edge case where we could potentially set the last_email_notified_at after require_by
              with_write_and_throttle do
                metadata.update_columns last_email_notified_at: query_start, email_notified_count: notified_count
              end
              GitHub.dogstats.increment("#{query_name}.total.count", tags: ["two_factor_enabled:#{two_factor_enabled}"])
              total_count += 1
            end
          end

          batch_elapsed = GitHub::Dogstats.duration(batch_start, Time.now.utc)
          GitHub.dogstats.distribution("#{query_name}.batch.duration", batch_elapsed)
        end
      end

      if total_count >= NOTIFY_LIMIT || timer.expired?
        reason = total_count >= NOTIFY_LIMIT ? "query" : "time"
        GitHub.dogstats.increment("two_factor_required_notifier.limit_reached", tags: ["reason:#{reason}"])
      end

      perform_elapsed = GitHub::Dogstats.duration(perform_start, Time.now.utc)
      GitHub.dogstats.distribution("two_factor_required_notifier.perform.duration", perform_elapsed)
    end
  end

  private


  def batches_for(scope, batch_size: BATCH_SIZE, &block)
    return unless block_given?

    # manually batch 2FA notifier queries to avoid sorting the entire join table. This dramatically speeds up the job.
    last_user_id = 0
    loop do
      query = scope.call.where("two_factor_requirement_metadata.user_id > ?", last_user_id)
      batch = query.order("two_factor_requirement_metadata.user_id asc").limit(batch_size)

      # We're converting `to_a` now very intentionally. We want ActiveRecord to evaluate the batch now, instead of having the first evaulation of the batch be `batch.size` in `perform_now` above.
      # That would require AR to execute a subquery that breaks the query optimizer hints added in TwoFactorRequirementMetadata scopes
      # optimizer hints added in https://github.com/github/github/pull/307929 and misuse by AR fixed in https://github.com/github/github/pull/308293
      evaluated_batch = batch.to_a
      break if evaluated_batch.empty?

      yield evaluated_batch
      last_user_id = T.cast(evaluated_batch.last.user_id, Integer)
    end
  end

  def with_write_and_throttle
    with_write do
      TwoFactorRequirementMetadata.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
        yield
      end
    end
  end
end
