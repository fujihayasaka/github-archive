# typed: strict
# frozen_string_literal: true

class GlobalNoticeNext
  class BusinessManualDunningCheck < BaseCheck
    extend T::Sig

    sig { override.returns(T::Boolean) }
    def should_show_notice?
      return false unless viewer.business_manual_dunning?
      @manual_dunning_business = T.let(viewer.manual_dunning_businesses.first, T.nilable(::Business))
      true
    end
  end
end
