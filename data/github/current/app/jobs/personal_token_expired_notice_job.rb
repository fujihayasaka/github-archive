# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class PersonalTokenExpiredNoticeJob < ApplicationJob
  queue_as :pat_expiry_notice_job

  exempt_from_tenant_context_requirement
  retry_on_dirty_exit

  schedule interval: 1.hour

  BATCH_SIZE = 1_000
  PAT_EXPIRED_EMAIL_TTL = 1.day

  def perform
    emails_sent = 0
    already_sent = 0

    expired_personal_token_access_ids_in_batches_of(BATCH_SIZE) do |ids|
      OauthAccessTokens.domain.by_ids(ids).each do |oauth_access|
        options = {
          interval:   PAT_EXPIRED_EMAIL_TTL,
          user_id:   oauth_access.user_id,
          oauth_access_id: oauth_access.id,
          token_last_eight: oauth_access.token_last_eight,
        }

        # Use action restraint to avoid sending duplicates.
        if GitHub::ActionRestraint.perform?("pat_expired_email", **options)
          AccountMailer.pat_expired_notice(oauth_access).deliver_later
          emails_sent += 1
        else
          already_sent += 1
        end
      end
    end

    GitHub.dogstats.count("jobs.personal_token_expired_notice_job.emails_sent", emails_sent)
    GitHub.dogstats.count("jobs.personal_token_expired_notice_job.already_sent", already_sent)
  end

  private

  # Yields `batch_size` expired OauthAccess IDs, belonging to personal access
  # tokens (legacy and fine-grained), to the given block.
  #
  # We intentionally do the filtering and batching in Ruby, rather than SQL,
  # here to avoid a single query running longer than the low-performing
  # threshold for databasebot, which is currently 2 seconds.
  #
  # See:
  # https://github.com/github/mysql-database-usage/issues/1817#issuecomment-2573547352
  def expired_personal_token_access_ids_in_batches_of(batch_size)
    expired_oauth_accesses.pluck(:id, :application_id).each_slice(batch_size) do |slice|
      pat_access_ids = slice.filter_map do |id, application_id|
        id if application_id == OauthApplication::PERSONAL_TOKENS_APPLICATION_ID
      end

      yield pat_access_ids
    end
  end

  # All OauthAccess records that have expired within the last two hours.
  # We keep this query intentionally simple so that it executes quickly
  # (hopefully within 2 seconds).
  #
  # See:
  # https://github.com/github/mysql-database-usage/issues/1817#issuecomment-2573547352
  def expired_oauth_accesses
    now = Time.now.utc
    # Look back 2 hours
    start_time = now - 2.hours

    OauthAccess.where(
      "expires_at_timestamp >= ? AND expires_at_timestamp <= ?",
      start_time.to_i,
      now.to_i
    )
  end
end
