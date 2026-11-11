# typed: strict
# frozen_string_literal: true

module Search
  module Memex
    module Nodes
      # Shared deep-merge logic used by OrGroup and ParenGroup to combine compiled
      # Elasticsearch query fragments. Arrays are concatenated, hashes are recursively
      # merged, and scalar conflicts resolve to the newer value.
      module DeepMergeHelpers
        sig do
          params(
            hash_1: T::Hash[T.untyped, T.untyped],
            hash_2: T::Hash[T.untyped, T.untyped],
          ).returns(T::Hash[T.untyped, T.untyped])
        end
        private def deep_merge_query(hash_1, hash_2)
          return hash_2 if hash_1.empty?

          hash_1.deep_merge(hash_2) do |_key, oldval, newval|
            if oldval.is_a?(Array) || newval.is_a?(Array)
              Array.wrap(oldval) + Array.wrap(newval)
            elsif oldval.is_a?(Hash) && newval.is_a?(Hash)
              deep_merge_query(oldval, newval)
            else
              newval
            end
          end
        end
      end
    end
  end
end
