# typed: strict
# frozen_string_literal: true

module BranchProtections
  module Migration
    module Structs
      class CoverageStatus < T::Enum
        enums do
          FullyCovered = new(:fully_covered)
          PartiallyCovered = new(:partially_covered)
          NotCovered = new(:not_covered)
          Unknown = new(:unknown)
        end
      end
    end
  end
end
