# typed: strict
# frozen_string_literal: true

module GH
  module Dev
    module Sorbet
      class Sigil < T::Enum
        enums do
          False = new
          True = new
          Strict = new
          String = new
          Strong = new
          Ignore = new
        end
      end
    end
  end
end
