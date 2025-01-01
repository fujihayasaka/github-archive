# typed: strict
# frozen_string_literal: true

module EnterpriseNavigation
  class GroupType < T::Enum
    enums do
      # grouped links may be collapsed
      FOLDING = new
      # a folding group with a divider at the top, if a group exists before it
      FOLDING_WITH_DIVIDER = new
      # Will add a divider at the start of a group, if a group exists before it
      DIVIDER = new
      # no leading divider
      FLAT = new
    end
  end
end
