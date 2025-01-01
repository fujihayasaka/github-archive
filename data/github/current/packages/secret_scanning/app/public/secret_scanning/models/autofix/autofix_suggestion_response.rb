# typed: strict
# frozen_string_literal: true

module SecretScanning
  module Models
    module Autofix
      class AutofixSuggestionResponse < T::Struct
        const :explanation, String
        const :diff_lines, T::Array[T.untyped]
        const :accept_feedback, T::Boolean
      end
    end
  end
end
