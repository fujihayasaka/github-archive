# typed: true
# frozen_string_literal: true

class PersonalTokenExpiryNoticeJob < BatchedJob
  queue_as :pat_expiry_notice_job

  exempt_from_tenant_context_requirement
  retry_on_dirty_exit

  schedule interval: 1.day

  # uses default BATCH_SIZE of 100

  EXPIRING_THRESHOLD = 7.days

  ONE_DAY_NOTICE = "one_day_notice"
  SEVEN_DAY_NOTICE = "seven_day_notice"

  PAT_EXPIRY_EMAIL_TTL = 7.days

  def process_batch(records, *args, **options)

    emails_sent = 0
    already_sent = 0

    records.each do |oauth_access|
      # We notify the customer twice: a seven day notice and a one day notice
      # we use this value with ActionRestraint so that we email only once per "stage"
      notice_stage = if oauth_access.expires_at <= 1.day.from_now.utc
        ONE_DAY_NOTICE
      else
        SEVEN_DAY_NOTICE
      end

      options = {
        interval:   PAT_EXPIRY_EMAIL_TTL,
        user_id:   oauth_access.user_id,
        oauth_access_id: oauth_access.id,
        token_last_eight: oauth_access.token_last_eight,
        notice_stage: notice_stage
      }

      if GitHub::ActionRestraint.perform?("pat_expiry_email", **options)
        AccountMailer.pat_expiry_notice(oauth_access).deliver_later
        emails_sent += 1
      else
        already_sent += 1
      end
    end

    GitHub.dogstats.count("jobs.personal_token_expiry_notice_job.emails_sent", emails_sent)
    GitHub.dogstats.count("jobs.personal_token_expiry_notice_job.already_sent", already_sent)
  end

  def next_batch(timestamp: Time.now.utc, offset_item_id: 0, progress: 0, **options)
    expiring = timestamp + EXPIRING_THRESHOLD

    ActiveRecord::Base.connected_to(role: :reading_slow) do
      OauthAccess.throttle do
        OauthAccess
          .personal_tokens
          .where("expires_at_timestamp > ? AND expires_at_timestamp < ?", timestamp.to_i, expiring.to_i)
          .where("id > ?", offset_item_id)
          .order(:id)
          .limit(BATCH_SIZE)
          .to_a
      end
    end
  end
end
