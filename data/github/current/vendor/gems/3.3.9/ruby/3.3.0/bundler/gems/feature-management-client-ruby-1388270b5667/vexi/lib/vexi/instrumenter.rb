# frozen_string_literal: true
# typed: strict

require "sorbet-runtime"

module Vexi
  # Vexi instrumenter interface
  module Instrumenter
    # Sorbet doesn't support recursive type aliases, therefore allow hashes wiht untyped values for child-contexts
    NotificationContextValue = T.type_alias { T.any(String, Numeric, Time, T::Boolean, T::Array[String], T::Hash[Symbol, T.untyped]) }
    NotificationContext = T.type_alias { T::Hash[Symbol, NotificationContextValue] }
  end
end
