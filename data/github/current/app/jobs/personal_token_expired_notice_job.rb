# typed: true
# frozen_string_literal: true

class PersonalTokenExpiredNoticeJob < ApplicationJob
  queue_as :pat_expiry_notice_job

  exempt_from_tenant_context_requirement
  retry_on_dirty_exit

  schedule interval: 1.hour

  PAT_EXPIRED_EMAIL_TTL = 1.day

  def perform
    now = Time.now.utc
    # Look back 2 hours, use action restraint to avoid sending duplicates
    start_time = now - 2.hours

    emails_sent = 0
    already_sent = 0

    OauthAccess
      .personal_tokens
      .where("expires_at_timestamp >= ? AND expires_at_timestamp <= ?", start_time.to_i, now.to_i)
      .find_each do |oauth_access|
      options = {
        interval:   PAT_EXPIRED_EMAIL_TTL,
        user_id:   oauth_access.user_id,
        oauth_access_id: oauth_access.id,
        token_last_eight: oauth_access.token_last_eight,
      }

      if GitHub::ActionRestraint.perform?("pat_expired_email", **options)
        AccountMailer.pat_expired_notice(oauth_access).deliver_later
        emails_sent += 1
      else
        already_sent += 1
      end
    end

    GitHub.dogstats.count("jobs.personal_token_expired_notice_job.emails_sent", emails_sent)
    GitHub.dogstats.count("jobs.personal_token_expired_notice_job.already_sent", already_sent)
  end
end
