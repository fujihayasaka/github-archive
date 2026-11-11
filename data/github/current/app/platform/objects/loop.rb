# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    # Alias the nested Loops::Loop GraphQL object to the top-level expected
    # constant name so permission checks that constantize `Platform::Objects::<Type>`
    # (using the GraphQL type name "Loop") function correctly.
    #
    # The underlying definition lives at `Platform::Objects::Loops::Loop`.
    Loop = Loops::Loop
  end
end
