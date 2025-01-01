# typed: true
# frozen_string_literal: true

module ContextRegion
  class RootCrumb < Crumb
    def label
      "GitHub"
    end

    def is_root?
      true
    end
  end
end
