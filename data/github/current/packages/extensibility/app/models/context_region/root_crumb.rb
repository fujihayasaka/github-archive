# typed: strict
# frozen_string_literal: true

module ContextRegion
  class RootCrumb < Crumb
    sig { override.returns(String) }
    def label
      "GitHub"
    end

    sig { override.returns(T::Boolean) }
    def is_root?
      true
    end
  end
end
