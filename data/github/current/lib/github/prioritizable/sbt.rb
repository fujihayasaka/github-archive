# typed: strict
# frozen_string_literal: true

module GitHub
  module Prioritizable
    module SBT
      autoload :Position, "github/prioritizable/sbt/position"
      autoload :Item, "github/prioritizable/sbt/item"
      autoload :Context, "github/prioritizable/sbt/context"
    end
  end
end
