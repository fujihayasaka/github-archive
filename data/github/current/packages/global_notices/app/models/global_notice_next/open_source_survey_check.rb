# typed: strict
# frozen_string_literal: true

class GlobalNoticeNext
  class OpenSourceSurveyCheck < BaseCheck
    sig { returns(String) }
    def type
      "info"
    end

    sig { returns(T::Boolean) }
    def should_show_notice?
      false
    end
  end
end
