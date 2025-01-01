# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class OtpSmsTimingCleanupJob < ApplicationJob
  retry_on_dirty_exit
  schedule interval: 1.minute, condition: -> { !GitHub.enterprise? }

  # don't allow this job to run concurrently
  locked_by timeout: 1.hour, key: DEFAULT_LOCK_PROC

  queue_as :otp_sms_timing_cleanup

  # this job does not run in Proxima since 2FA isn't supported
  exempt_from_tenant_context_requirement

  def perform
    return unless GitHub.two_factor_sms_enabled?
    expired = OtpSmsTiming.expired_outstanding
    return if expired.empty?

    expired_data = expired.map(&:attributes)

    # perform the actual cleanup
    with_write do
      delete_keys(expired)
    end

    # log the timing data to datadog so we can continue tracking "unused" SMS
    uids = expired_data.map { |e| e["user_id"] }

    # OTP SMS Timings are only applicable to primary SMS.
    # Note this would need to be refactored if we ever support multiple primary SMS registrations per user,
    # because the OtpSmsTiming only tracks provider and user_id with no way of knowing which registration was used.
    regs = SmsRegistration.where(user_id: uids, is_primary: 1)
    # save these for metrics
    unupdatable_registrations = regs.filter { |r| r.consecutive_missed_otp_count = 255 }

    with_write do
      # filter out registrations that have hit the 255 max value for the consecutive_missed_otp_count column that can no longer be incremented
      success = regs.where("consecutive_missed_otp_count < 255").update_all("consecutive_missed_otp_count = consecutive_missed_otp_count + 1 ")
      GitHub.dogstats.increment "increment_consecutive_missed_otp_count", tags: ["success:#{success}"]
    end

    regs.each do |reg|
      next unless country = GitHub::TwoFactorAuthentication.sms_country_code(reg.sms_number)
      GitHub.dogstats.increment "two_factor.sms_timing", tags: ["action:dropped", "provider:#{reg.sms_provider}", "country:#{country}", "store:mysql"]
    end

    # track how often we're at the column size limit
    unupdatable_registrations.each do |reg|
      next unless country = GitHub::TwoFactorAuthentication.sms_country_code(reg.sms_number)
      GitHub.dogstats.increment "two_factor.sms_timing.maxed_missed_count", tags: ["action:dropped", "provider:#{reg.sms_provider}", "country:#{country}", "store:mysql"]
    end
  end

  # Delete a set of keys
  #
  # keys - An Array of OtpSmsTiming objects.
  #
  # Returns nothing.
  def delete_keys(keys)
    keys.delete_all
  end
end
