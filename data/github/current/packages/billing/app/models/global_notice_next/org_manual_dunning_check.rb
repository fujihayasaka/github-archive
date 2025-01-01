# typed: strict
# frozen_string_literal: true

class GlobalNoticeNext
  class OrgManualDunningCheck < BaseCheck

    sig { override.returns(T::Boolean) }
    def should_show_notice?
      return false unless viewer.org_manual_dunning?
      @manual_dunning_org = T.let(viewer.manual_dunning_orgs.first, T.nilable(::Organization))
      true
    end
  end
end
