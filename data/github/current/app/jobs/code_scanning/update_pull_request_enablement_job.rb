# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

# CodeScanning::UpdatePullRequestEnablementJob runs on a delay after a pull request is opened.
# If the pull request still does not have an analysis after this delay, the status of pull request analysis will be updated to "disabled".
class CodeScanning::UpdatePullRequestEnablementJob < ApplicationJob
  queue_as :code_scanning

  before_perform do |job|
    Failbot.push(job: job.class.name)
  end

  retry_on_dirty_exit
  retry_on ::Repository::SecurityCenterDependency::UnknownSecurityFeatureStatusError, wait: :polynomially_longer

  def self.should_perform?(repository:)
    return false if repository.nil?
    return false if repository.deleted?
    return false unless repository.code_scanning_enabled?
    return false unless repository.owner.organization?
    return false unless ::SecurityCenter::SecurityFeatures.visible_features(repository.owner).include?(::SecurityCenter::SecurityFeatures::CODE_SCANNING)
    # Security Center considers Code Scanning to be in an unknown state for a repository if its alerts do not have a severity. We are unclear about the motivation.
    # This causes an error if we attempt to update the pull request review status.
    # To avoid this, we don't attempt to update the pull request review status unless the status for Code Scanning is known.
    return false if repository.code_scanning_security_center_status.nil?
    true
  end

  def perform(repository_id:)
    repository = Repositories::Public.get_active_or_deleted(repository_id)
    return unless self.class.should_perform?(repository: repository)
    repository = T.must(repository)
    repository.security_center_notify(
      :code_scanning_pr_reviews,
      source_event: "pull_request_opened",
    )

    ::SecurityOverviewAnalytics::CodeScanningPullRequestAlertsFeatureToggledJob.perform_later(
      repository_id:,
      source_event: "pull_request_opened",
    )
  end
end
