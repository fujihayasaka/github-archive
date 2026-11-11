# typed: true
# frozen_string_literal: true

# This job bulk purges old ruleset artifacts like history and insights
class RulesetSweeperJob < ApplicationJob
  queue_as :ruleset_sweeper
  retry_on_dirty_exit
  retry_on Faraday::TimeoutError

  schedule interval: 1.minute
  locked_by timeout: 1.minute, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC

  exempt_from_tenant_context_requirement

  BATCH_SIZE = 3000

  def self.expiration_period
    180.days
  end

  def perform
    end_date = Time.now - RulesetSweeperJob.expiration_period - 12.hours
    batch_size = compute_batch_size
    GitHub.dogstats.gauge("ruleset_sweeper_job.batch_size", batch_size)

    destroy_ruleset_history(end_date, batch_size)
    destroy_rule_suites(end_date, batch_size)
  end

  private

  def high_replication_lag?
    delay = Freno.client.replication_delay(store_name: :repositories)
    delay > 0.5 # seconds. Normal delay is around 0.31 seconds
  rescue Freno::Error
    true
  end

  def compute_batch_size
    max_batch_size = BATCH_SIZE
    # FF 1% => batch_size == 100
    # FF 100% => batch_size == 10_000
    if FeatureFlag.vexi.percentage_of_calls_value_or_raise(:ruleset_sweeper_batch_size) > 0 # rubocop:disable GitHub/FeatureManagement/NoVexiNonStandardUsage
      max_batch_size = (FeatureFlag.vexi.percentage_of_calls_value_or_raise(:ruleset_sweeper_batch_size) * 100).to_i # rubocop:disable GitHub/FeatureManagement/NoVexiNonStandardUsage
    end

    # during times of high replication lag, drop batch size to 0
    batch_size = high_replication_lag? ? 0 : max_batch_size
  end

  def destroy_rule_suites(end_date, batch_size)
    scope = RuleEngine::RuleSuite.where("created_at < ?", end_date).annotate("cross-shard-query-exempted")
    if FeatureFlag.vexi.enabled?(:ruleset_sweeper_avoid_big_count, default: false)
      earliest_expired = scope.order(created_at: :asc).limit(1).pluck(:created_at).first
      if earliest_expired.nil?
        GitHub.dogstats.gauge("ruleset_sweeper_job.lag.minutes", 0)
      else
        lag = (end_date - earliest_expired).to_i / 60.0
        GitHub.dogstats.gauge("ruleset_sweeper_job.lag.minutes", lag)
      end
    else
      expired = scope.limit(5_000_000).count
      GitHub.dogstats.gauge("ruleset_sweeper_job.expired_rule_suites", expired)
    end

    return unless batch_size > 0

    count = 0
    scope.order(created_at: :asc).limit(batch_size).in_batches(of: 100) do |batch|
      count += batch.size
      with_write do
        batch.destroy_all
      end
    end

    GitHub.dogstats.gauge("ruleset_sweeper_job.destroyed_rule_suites", count)
  end

  def destroy_ruleset_history(end_date, batch_size)
    expired = RepositoryRulesetHistory.where("created_at < ?", end_date).limit(1_000_000).count
    GitHub.dogstats.gauge("ruleset_sweeper_job.expired_ruleset_histories", expired)

    return unless batch_size > 0
    count = 0
    RepositoryRulesetHistory.where("created_at < ?", end_date).order(created_at: :asc).limit(batch_size).in_batches(of: 100) do |batch|
      count += batch.size
      with_write do
        # We call delete_all instead of destroy_all to avoid loading the records.
        # Some have huge 1 million+ byte `state` fields which can cause SQL to blow up
        # There are no on_destroy callbacks so we're safe to use delete_all
        batch.delete_all
      end
    end

    GitHub.dogstats.gauge("ruleset_sweeper_job.destroyed_ruleset_histories", count)
  end
end
