# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class PageCertificateRenewJob < ApplicationJob
  queue_as :pages_https

  locked_by key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC, timeout: ApplicationJob::DEFAULT_TIMEOUT

  # We're allowed 300 outstanding authorizations by LE. Stay under that.
  # Expired domains should be rare – usually due to one-off incidents (e.g.
  # https://github.com/github/pages/issues/2145) – so we allocate only a small
  # rate for them.
  EXPIRED_BATCH_SIZE = 2
  FUTURE_EXPIRY_BATCH_SIZE = 15

  ROTATE_CERTIFICATE_NAME = "github_sni_6.key"

  def perform
    Failbot.push(app: "pages-certificates")
    Page::Certificate.throttle do
      # We're allowed 300 outstanding authorizations by LE. Stay under that.
      future_expiry_batch_size = FeatureFlag.vexi.enabled_or_raise?(:pages_emergency_renewal_higher_batch) ? 40 : FUTURE_EXPIRY_BATCH_SIZE # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage

      future_expiry_scope =
        if FeatureFlag.vexi.enabled_or_raise?(:pages_emergency_renewal) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
          # In the next phase of cleanup, we try to renew certificates
          # which are using the old thumbprint despite the model saying otherwise.
          # A good heuristic to find such domains seems to be to compare updated_at and expires_at because
          # the first renewal attemp did change updated_at to kept expires_at to the old original expiration date
          # of the old certificate. This result in a difference typically < 90 (which is the validity of a regular LE certificate).
          Page::Certificate.where(<<-SQL, ROTATE_CERTIFICATE_NAME)
          ABS(DATEDIFF(updated_at, expires_at)) < 90 AND fastly_privkey_id = ? AND state = 7
          SQL
        else
          Page::Certificate.where(<<-SQL, Page::Certificate::RENEWAL_WINDOW.from_now)
            expires_at BETWEEN NOW() AND ?
          SQL
        end
      # Enqueue a PageCertificateWorkJob job for each cert needing renewal.
      future_expiry_selected = future_expiry_scope
        .order(Arel.sql("RAND()"))
        .limit(future_expiry_batch_size)
        .each(&:resume_flow)

      # Balance the jobs if we have more capacity in the batch
      if FeatureFlag.vexi.enabled_or_raise?(:pages_balance_certificate_renewal) && future_expiry_scope.count < future_expiry_batch_size # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
        GitHub.dogstats.increment("pages.certificates.balancing_scope.started")

        remaining_capacity = future_expiry_batch_size - future_expiry_scope.count

        # Use the ID to group the certs into ideal months to renew, and take a random subset the size of the
        # remaining capacity to perform the job on.
        args = {
          renewal_window: Page::Certificate::RENEWAL_WINDOW.from_now,
          balancing_window_max: Page::Certificate::RENEWAL_BALANCING_MAX_EXPIRES_AT.from_now,
          month_mod: Time.now.month % 3
        }
        additional_cert_scope =
        Page::Certificate.where(<<-SQL, **args)
        SELECT MOD(id, 3) = :month_mod WHERE expires_at BETWEEN :renewal_window AND :balancing_window_max
        SQL

        balanced_jobs = additional_cert_scope
          .limit(remaining_capacity)
          .each(&:resume_flow)

        GitHub.dogstats.increment("pages.certificates.balancing_scope.ended")
        GitHub.dogstats.count("pages.certificates.balancing_scope", balanced_jobs.count)
      end

      # Check for domains that are approved but expired, which means we failed
      # to renew their certs in time.
      expired_domain_scope = Page::Certificate.where(<<-SQL, Page::Certificate.states[:approved])
        state = ? AND expires_at <= NOW()
      SQL
      # Enqueue a PageCertificateWorkJob job for each cert needing renewal.
      expired_domain_selected = expired_domain_scope.order(Arel.sql("RAND()")).limit(EXPIRED_BATCH_SIZE).each(&:resume_flow)

      GitHub.dogstats.count("pages.certificates.future_expiry_scope", future_expiry_selected.count)
      GitHub.dogstats.count("pages.certificates.expired_domain_scope", expired_domain_selected.count)
    end
  end

  retry_on_dirty_exit
end
