# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class MergeQueueMergingStrategy < Platform::Enums::Base
      description "The possible merging strategies for a merge queue."

      value "ALLGREEN",    "Entries only allowed to merge if they are passing.", value: "ALLGREEN"
      value "HEADGREEN",   "Failing Entires are allowed to merge if they are with a passing entry.", value: "HEADGREEN"
    end
  end
end
