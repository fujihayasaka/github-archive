# typed: true
# frozen_string_literal: true

class SetupIssueFieldsForOrganizationJob < ApplicationJob
  use_primaries ApplicationRecord::IssuesPullRequests

  queue_as :setup_issue_fields_for_organization

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  def perform(org:)
    return if FeatureFlag.vexi.enabled?(:default_issue_fields_job_killswitch, default: false)

    with_write do
      IssueField::Defaults.create_default_issue_fields_for(org)
    end
  end
end
