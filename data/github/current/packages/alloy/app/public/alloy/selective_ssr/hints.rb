# typed: strict
# frozen_string_literal: true

module Alloy
  class SelectiveSsr
    class Hints < T::Struct
      const :highly_cacheable, T.nilable(T::Boolean)
      const :no_js_experience, T.nilable(T::Boolean)
    end
  end
end
