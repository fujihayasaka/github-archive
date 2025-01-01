# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class DiffSide < Platform::Enums::Base
      graphql_name "DiffSide"
      description "The possible sides of a diff."

      value "LEFT", "The left side of the diff.", value: :left
      value "RIGHT", "The right side of the diff.", value: :right
    end
  end
end
