# typed: true
# frozen_string_literal: true

module GitHub
  class SQL
    module ArelLiterals
      NOW = Arel.sql("NOW()")

      def self.binary(value)
        ActiveModel::Type::Binary::Data.new(value)
      end
    end
  end
end
