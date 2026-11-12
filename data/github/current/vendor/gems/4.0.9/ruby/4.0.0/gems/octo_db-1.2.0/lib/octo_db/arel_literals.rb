# typed: strict
# frozen_string_literal: true

require "active_model"
require "arel"

module OctoDb
  module ArelLiterals
    extend T::Sig

    NOW = T.let(Arel.sql("NOW()"), Arel::Nodes::SqlLiteral)

    sig { params(value: T.untyped).returns(ActiveModel::Type::Binary::Data) }
    def self.binary(value)
      ActiveModel::Type::Binary::Data.new(value)
    end
  end
end
