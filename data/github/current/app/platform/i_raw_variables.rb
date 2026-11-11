# typed: strict
# frozen_string_literal: true

module Platform
  IRawVariables = T.type_alias { T.any(T.nilable(String), IVariables, Integer, T::Array[T.untyped], T::Boolean) }
end
