# typed: strict
# frozen_string_literal: true

class GlobalNoticeNext
  class DisabledOrgBillingCheck < BaseCheck

    sig { override.returns(String) }
    def type
      "error"
    end

    sig { override.returns(T::Boolean) }
    def should_show_notice?
      return false unless viewer.disabled_orgs?
      @troubled_org = T.let(viewer.disabled_orgs.first, T.nilable(::Organization))
      true
    end
  end
end
