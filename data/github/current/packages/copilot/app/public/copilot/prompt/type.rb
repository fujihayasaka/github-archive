# typed: strict
# frozen_string_literal: true

module Copilot
  module Prompt
    module Type
      extend T::Sig

      TokenRange = T.type_alias { T::Range[Integer] }
    end
  end
end
