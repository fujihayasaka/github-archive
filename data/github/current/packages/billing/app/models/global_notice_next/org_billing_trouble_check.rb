# typed: strict
# frozen_string_literal: true

class GlobalNoticeNext
  class OrgBillingTroubleCheck < BaseCheck
    extend T::Sig

    sig { override.returns(T::Boolean) }
    def should_show_notice?
      return false unless viewer.org_billing_trouble?
      @troubled_org = T.let(viewer.billing_troubled_orgs.first, T.nilable(::Organization))
      true
    end
  end
end
