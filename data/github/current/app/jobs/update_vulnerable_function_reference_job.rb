# typed: true
# frozen_string_literal: true

class UpdateVulnerableFunctionReferenceJob < ApplicationJob
  queue_as :vulnerability_exposure_analysis

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  def perform(affected_functions_hash: nil, affected_functions_json: nil, vulnerability_ids: [])
    if affected_functions_hash
      affected_functions_hash.each do |vvr_id, (affected_functions_before, affected_functions_after)|
        if affected_functions_before.present? && affected_functions_after.empty?
          # This means all affected functions have been removed
          # Thus we need to delete their corresponding RepositoryVulnerabilityFunctionReferences
          DeleteDependentRecordsJob.perform_later("VulnerableVersionRange", vvr_id, :repository_vulnerable_function_references)
        else
          # Find all alerts with respect to the vulnerable version range whose affected fucntions have changed
          # and enqueue a job to update the alert's function references
          GitHub.dogstats.distribution_time("update_vulnerable_function_reference_job.process_affected_functions_hash.time") do
            RepositoryVulnerabilityAlert.where(vulnerable_version_range_id: vvr_id).select(:id).in_batches do |batch|
              batch.pluck(:id).each do |alert_id|
                UpdateAlertVulnerabilityExposureJob.perform_later(alert_id: alert_id)
              end
            end
          end
        end
      end
    end

    if affected_functions_json
      affected_functions_json.each do |vvr_id, (affected_functions_before, affected_functions_after)|
        if affected_functions_before.present? && affected_functions_after.empty?
          # This means all affected functions json have been removed
          # Thus we need to delete their corresponding RepositoryVulnerabilityFunctionReferences
          DeleteDependentRecordsJob.perform_later("VulnerableVersionRange", vvr_id, :repository_vulnerable_function_references)
        else
          # Find all alerts with respect to the vulnerable version range whose affected fucntions json have changed
          # and enqueue a job to update the alert's function references
          GitHub.dogstats.distribution_time("update_vulnerable_function_reference_job.process_affected_functions_json.time") do
            RepositoryVulnerabilityAlert.where(vulnerable_version_range_id: vvr_id).select(:id).in_batches do |batch|
              batch.pluck(:id).each do |alert_id|
                UpdateAlertVulnerabilityExposureJob.perform_later(alert_id: alert_id)
              end
            end
          end
        end
      end
    end

    if vulnerability_ids.present?
      GitHub.dogstats.distribution_time("update_vulnerable_function_reference_job.process_vulnerability_ids.time") do
        RepositoryVulnerabilityAlert.where(vulnerability_id: vulnerability_ids).select(:id).in_batches do |batch|
          batch.pluck(:id).each do |alert_id|
            UpdateAlertVulnerabilityExposureJob.perform_later(alert_id: alert_id)
          end
        end
      end
    end
  end
end
