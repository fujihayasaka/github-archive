# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Groupable
  # Options for ordering the "no value" group first or last (default).
  #
  # The most common deviation from the default of last is on the board view,
  # where we always request the "no value" group first.
  class MissingValueGroupOrder < T::Enum
    enums do
      First = new
      Last = new
    end
  end
end
