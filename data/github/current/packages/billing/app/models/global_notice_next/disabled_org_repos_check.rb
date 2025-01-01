# typed: true
# frozen_string_literal: true

class GlobalNoticeNext
  class DisabledOrgReposCheck < BaseCheck
    extend T::Sig

    sig { override.returns(String) }
    def type
      "error"
    end

    sig { override.returns(T::Boolean) }
    def should_show_notice?
      !!viewer.org_over_plan_limit?
    end
  end
end
