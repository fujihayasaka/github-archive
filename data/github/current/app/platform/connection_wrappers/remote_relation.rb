# typed: true
# frozen_string_literal: true

module Platform
  module ConnectionWrappers
    class RemoteRelation < Relation
      attr_reader :count

      def initialize(remote_relation, **kwargs)
        @count = remote_relation.count
        super(remote_relation.relation, **kwargs)
      end

      def total_count
        count
      end
    end
  end
end
