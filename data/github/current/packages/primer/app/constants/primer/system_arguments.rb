# typed: true
# frozen_string_literal: true

module Primer
  # If typing rest parameters, use SystemArgumentsValue instead
  SystemArguments = T.type_alias do
    T::Hash[
      # key
      T.any(Symbol, String),

      # value
      SystemArgumentsValue
    ]
  end
end
