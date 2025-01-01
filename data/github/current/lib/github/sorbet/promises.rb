# typed: strict
# frozen_string_literal: true

# Union types and generics have interoperability issues.
#
# The following code yields the following type which is not compatible with a T::Boolean:
#   > Promise.resolve(true) #=> Promise[TrueClass]
#
# This module exposes a collection of pre-generated Promise types to support the scenario where union generic types
# are required. Sorbet prevents adding type aliases to a generic class, so this must be in a different namespace.
module Promises
  extend T::Helpers

  Boolean = T.type_alias do
    T.any(
      Promise[T::Boolean],
      Promise[TrueClass],
      Promise[FalseClass]
    )
  end
end
