# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

module Actions
  class UpdateNonUsedCustomPoolsJob < ApplicationJob
    include Actions::LargerRunnersHelper
    include Actions::LargerRunnersControllerHelper

    queue_as :actions_non_used_pools_update_job

    retry_on_dirty_exit
    retry_on_recoverable_exceptions

    RetryableError = Class.new(RuntimeError)
    retry_on RetryableError, OpenSSL::SSL::SSLErrorWaitReadable, Faraday::TimeoutError, wait: 1.minute, attempts: 5

    def perform(entity:)
      return if entity.nil?
      return unless entity.is_a?(Organization) || entity.is_a?(Business)
      return unless entity.is_larger_runners_onboarded?
      return if entity.spammy?

      execution_timer = Timer.start

      days_to_expire = ::Actions::LargerRunner::PublicIPSettings.max_non_used_days_for(entity)

      # Executing the job against an Organization as part of an Enterprise will return not only Organization level runners but also those shared within the Enterprise
      # To prevent breaking the group mapping for other Organizations, we filter these runners out.
      # Public IP for these runners will be handled during execution of the job at the Enterprise level.
      expired_runners_with_public_ips = ::Actions::LargerRunner.larger_runners_for(entity: entity, is_public_ip_enabled: true)
        .reject(&:inherited?)
        .reject do |runner|
          # Ignore deleting/provisioning runners since we can't transition them to provisioning to delete the public IP
          runner.is_in_deleting_state? || runner.is_in_provisioning_state?
        end
        .filter_map do |runner|
          today = Date.today
          last_active_on = Date.parse(runner.last_active_on)

          runner if (today - last_active_on).to_i > days_to_expire
        end

      return unless expired_runners_with_public_ips.any?

      updated_pools_names = []
      expired_runners_with_public_ips.each do |runner|
        entity_login = entity.is_a?(Business) ? entity.slug : entity.login

        # Here in the model labels are array of objects, and UpdatePoolRequest model validation fails.
        # Assignments of [] indicates that we are not updating labels and also passes the validation
        runner.labels = []

        runner.is_public_ip_enabled = false

        result = update_larger_runners_for(entity, larger_runner: runner, actor: nil)
        report_error("Unable to update Pool: Pool ID: #{runner.id}, Entity ID: #{entity.id}, Entity Name: #{entity_login}") unless result.call_succeeded?

        updated_pools_names.push(runner.name)
      end

      execution_timer.stop
      GitHub.dogstats.distribution("active_job.actions.larger_runners.update_non_used_pools_job.duration_ms", execution_timer.elapsed_ms)
      GitHub.dogstats.increment("active_job.actions.larger_runners.update_non_used_pools_job", tags: ["status:success"])

      Actions::LargerRunnersNonUsageMailer.disable_public_ip_and_email(entity, days_to_expire, updated_pools_names).deliver_later
    end

    def report_error(error)
      GitHub.dogstats.increment("active_job.actions.larger_runners.update_non_used_pools_job", tags: ["status:failure"])

      Failbot.report(RuntimeError.new(error))

      raise RetryableError
    end
  end
end
