# typed: true
# frozen_string_literal: true

class GlobalNoticeNext
  class LowTwoFactorMethodsCheck < BaseCheck
    extend T::Sig

    SNOOZE_INTERVAL = T.let(3.months, ActiveSupport::Duration)

    sig { returns(T::Boolean) }
    def should_show_notice?
      viewer.show_low_two_factor_method_banner?
    end

    sig { returns(T::Boolean) }
    def can_snooze?
      true
    end

    sig { void }
    def snooze
      viewer.dismiss_notice(:low_two_factor_methods, expires: SNOOZE_INTERVAL.from_now, kv_store: GitHub::Authentication::KV.store)
    end
  end
end
