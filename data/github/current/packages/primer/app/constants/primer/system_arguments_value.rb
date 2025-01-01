# typed: true
# frozen_string_literal: true

module Primer
  # Use SystemArgumentsValue for typing rest parameters
  SystemArgumentsValue = T.type_alias do
    T.any(
      Symbol,
      String,
      Numeric,
      T::Boolean,

      # responsive values are passed as arrays
      T::Array[T.nilable(T.any(String, Integer, Symbol, T::Boolean))],

      # aria: { ... } and data: { ... }
      T::Hash[
        # key (:aria, "aria", :data, or "data")
        T.any(Symbol, String),

        # value (possibly a nested hash)
        T.any(Symbol, String, T::Hash[
          # key inside aria or data hash
          T.any(Symbol, String),

          # value
          T.nilable(T.any(Symbol, String, Numeric, T::Boolean))
        ])
      ]
    )
  end
end
