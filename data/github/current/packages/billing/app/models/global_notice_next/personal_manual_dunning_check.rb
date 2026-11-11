# typed: strict
# frozen_string_literal: true

class GlobalNoticeNext
  class PersonalManualDunningCheck < BaseCheck

    sig { override.returns(T::Boolean) }
    def should_show_notice?
      viewer.manual_dunning?
    end
  end
end
