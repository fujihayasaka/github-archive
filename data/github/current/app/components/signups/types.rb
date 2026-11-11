# typed: strict
# frozen_string_literal: true

# Define a shared module for reusable types
# rubocop:disable ViewComponent/ComponentsHaveUnitTests
module Signups

  module Types
    CustomPageType = T.type_alias do
      T::Hash[ # Each element in the array is a hash
        String, # Keys in the hash are strings
        T.any(  # Values can be any of the following:
          String,          # A regular string
          T.nilable(String), # A string or nil
          T::Boolean       # A boolean (true/false)
        )
      ]
    end
  end
end
