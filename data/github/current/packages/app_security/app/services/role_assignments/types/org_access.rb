# typed: strict
# frozen_string_literal: true

module RoleAssignments
  module Types
    class OrgAccess < T::Struct
      const :target, String
      const :selected_count, T.nilable(Integer)
      const :total_count, T.nilable(Integer)
      const :limit, T.nilable(Integer)

      # Define serialization for React payload
      sig { params(options: T.untyped).returns(T::Hash[Symbol, T.untyped]) }
      def as_json(options = {})
        {
          target:,
          selected_count:,
          total_count:,
          limit:
        }.compact
      end
    end
  end
end
