# typed: strict
# frozen_string_literal: true

module Elastomer
  module Interfaces
    module Document
      module MemexProjectItem
        # Represents the issue for an issue dependency/relationship, such as "blocked by" or "blocking".
        class DependencyIssue < T::Struct
          # The database ID of the issue
          prop :id, Integer
          # The name-with-owner reference of the issue, e.g., "owner/repo"
          prop :nwo_reference, String
          # The database ID of the repository owner
          prop :owner_id, Integer

          # Returns a `Hash` representation of the DependencyIssue.
          sig { returns(T::Hash[Symbol, T.any(Integer, String)]) }
          def to_hash
            {
              id: id,
              nwo_reference: nwo_reference,
              owner_id: owner_id,
            }
          end
        end
      end
    end
  end
end
