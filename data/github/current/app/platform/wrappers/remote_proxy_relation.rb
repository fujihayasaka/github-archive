# typed: true
# frozen_string_literal: true

module Platform
  module Wrappers
    class RemoteProxyRelation
      attr_accessor :relation, :count

      delegate :to_a, to: :relation

      def initialize(relation, count:)
        @relation = relation
        @count = count
      end
    end
  end
end
