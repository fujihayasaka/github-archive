# typed: true
# frozen_string_literal: true

class GlobalNoticeNext
  class SmsLowAvailabilityCountryCheck < BaseCheck

    SNOOZE_INTERVAL = T.let(30.days, ActiveSupport::Duration)

    sig { returns(T::Boolean) }
    def should_show_notice?
      viewer.show_sms_low_availability_country_banner?
    end

    def can_snooze?
      true
    end

    def snooze
      viewer.dismiss_notice(:sms_low_availability_country, expires: SNOOZE_INTERVAL.from_now, kv_store: GitHub::Authentication::KV.store)
    end
  end
end
