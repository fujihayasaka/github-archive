# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class TrackCodeScanningCheckRunDelayJob < ApplicationJob
  COMPLETION_TIME_TARGET = 5.minutes
  SLO_TARGET = 15.minutes

  queue_as :code_scanning

  before_perform do |job|
    context = {
      job: job.class.name,
      check_run_id: job.arguments.first,
    }
    Failbot.push(context)
  end

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  def perform(check_run_id, target: nil)
    check_run = Checks.domain.check_runs.unsafe_for_id(check_run_id)
    return if check_run.nil?

    if target == :completion_time
      GitHub.dogstats.increment("code_scanning.check_run.target_time_elapsed", tags: ["completed:#{check_run.completed?}"])
      GitHub.logger.info(
        "Check run target time has elapsed.",
        "code.namespace" => "TrackCodeScanningCheckRunDelayJob",
        "code.function" => "perform",
        "gh.repo.id" => check_run.repository_id,
        "gh.check_run.id" => check_run.id,
        "gh.check_run.status" => check_run.status,
        "gh.check_run.completed" => check_run.completed?,
      )
    elsif target == :slo
      GitHub.dogstats.increment("github/code_scanning.slo", tags: ["name:availability/check_run_delay", "success:#{check_run.completed?}"])
    end
  end

  def self.schedule(check_run_id)
    set(wait: COMPLETION_TIME_TARGET).perform_later(check_run_id, target: :completion_time)
    set(wait: SLO_TARGET).perform_later(check_run_id, target: :slo)
  end
end
