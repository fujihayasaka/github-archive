# typed: true
# frozen_string_literal: true

class NotifyOrgAdminsAboutPatRequestsJob < ApplicationJob
  ORG_BATCH_LIMIT = 1_000
  TIME_LIMIT = 4.minutes
  PAT_ORG_REQUEST_EMAIL_TTL = 2.hours

  queue_as :pat_access_request_notice_job
  schedule interval: 24.hours

  retry_on_dirty_exit

  exempt_from_tenant_context_requirement

  def perform(next_org_id = nil)
    GitHub::SafeTimer.timeout(TIME_LIMIT) do |timer|
      notify_orgs_with_requests(timer, next_org_id)
    end
  end

  private

  def notify_orgs_with_requests(timer, next_org_id)
    total_notified = 0
    total_already_notified = 0
    organization_ids = ProgrammaticAccessGrantRequest.targeted_organization_ids(next_id: next_org_id)

    organization_ids.in_groups_of(ORG_BATCH_LIMIT) do |batch_org_ids|
      if timer.expired?
        self.class.perform_later(batch_org_ids.first)
        return
      end

      Organization.where(id: batch_org_ids).each do |org|
        options = {
          interval: PAT_ORG_REQUEST_EMAIL_TTL,
          org_id: org.id,
        }

        if GitHub::ActionRestraint.perform?("pat_org_request_email", **options)
          OrganizationMailer.pat_access_request_notice(org).deliver_later
          total_notified += 1
        else
          total_already_notified += 1
        end

      end
    end

    GitHub.dogstats.count("jobs.pat_access_request_notice_job.org_notified", total_notified)
    GitHub.dogstats.count("jobs.pat_access_request_notice_job.org_already_notified", total_already_notified)
  end
end
