# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class MergeQueueMethod < Platform::Enums::Base
      description "Represents available types of methods to use when merging a pull request."

      value "GROUP", "Add to the merge queue and merge in a group", value: :group
      value "SOLO", "Add to the merge queue and merge in a solo merge group", value: :solo
      value "JUMP", "Jump to the front of the merge queue and merge in a solo merge group", value: :jump
    end
  end
end
