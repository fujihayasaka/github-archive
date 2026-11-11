# typed: strict
# frozen_string_literal: true

module GitHub
  module Transitions
    module Iterators
      autoload :Base, "github/transitions/iterators/base"
      autoload :DatabaseTable, "github/transitions/iterators/database_table"
      autoload :Csv, "github/transitions/iterators/csv"
    end
  end
end
