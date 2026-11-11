# typed: strict
# frozen_string_literal: true

module MergeQueues
  # All the required checks for the target Branch Protection rule.
  class Entry::RequiredCheck < T::Struct
    const :name, String
    const :integration_id, T.nilable(Integer)
  end
end
