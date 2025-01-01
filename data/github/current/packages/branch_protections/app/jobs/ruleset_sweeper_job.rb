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
    if GitHub.flipper[:ruleset_sweeper_batch_size].percentage_of_time_value > 0
      max_batch_size = (GitHub.flipper[:ruleset_sweeper_batch_size].percentage_of_time_value * 100).to_i
    end

    # during times of high replication lag, drop batch size to 0
    batch_size = high_replication_lag? ? 0 : max_batch_size
  end

  def destroy_rule_suites(end_date, batch_size)
    expired = RuleEngine::RuleSuite.where("created_at < ?", end_date).limit(5_000_000).count
    GitHub.dogstats.gauge("ruleset_sweeper_job.expired_rule_suites", expired)

    return unless batch_size > 0

    batch = RuleEngine::RuleSuite.where("created_at < ?", end_date).order(created_at: :asc).limit(batch_size)
    with_write do
      batch.each do |rule_suite|
        rule_suite.destroy
      end
    end

    GitHub.dogstats.gauge("ruleset_sweeper_job.destroyed_rule_suites", batch.size)
  end

  def destroy_ruleset_history(end_date, batch_size)
    expired = RepositoryRulesetHistory.where("created_at < ?", end_date).limit(1_000_000).count
    GitHub.dogstats.gauge("ruleset_sweeper_job.expired_ruleset_histories", expired)

    return unless batch_size > 0

    batch = RepositoryRulesetHistory.where("created_at < ?", end_date).order(created_at: :asc).limit(batch_size)
    with_write do
      batch.each do |history|
        history.destroy
      end
    end

    GitHub.dogstats.gauge("ruleset_sweeper_job.destroyed_ruleset_histories", batch.size)
  end
end
