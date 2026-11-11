# typed: strict
# frozen_string_literal: true

module Repos
  module BranchProtections
    module Concerns
      module Structs
        extend ActiveSupport::Concern
        extend T::Helpers

        class ProtectedBranch < T::Struct
          const :id, Integer
          const :name, String

          sig { params(protected_branch: ::ProtectedBranch).returns(ProtectedBranch) }
          def self.serialize(protected_branch)
            ProtectedBranch.new(
              id: protected_branch.id,
              name: protected_branch.name,
            )
          end
        end
      end
    end
  end
end
