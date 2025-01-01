# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class PinnedDiscussionPattern < Platform::Enums::Base
      description "Preconfigured background patterns that may be used to style discussions pinned within a repository."

      value "DOT_FILL", "A solid dot pattern", value: "dot-fill"

      value "PLUS", "A plus sign pattern", value: "plus"

      value "ZAP", "A lightning bolt pattern", value: "zap"

      value "CHEVRON_UP", "An upward-facing chevron pattern", value: "chevron-up"

      value "DOT", "A hollow dot pattern", value: "dot"

      value "HEART_FILL", "A heart pattern", value: "heart-fill"
    end
  end
end
