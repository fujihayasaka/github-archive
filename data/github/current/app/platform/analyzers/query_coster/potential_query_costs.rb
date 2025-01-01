# typed: strict
# frozen_string_literal: true

module Platform
  module Analyzers
    class QueryCoster
      class PotentialQueryCosts < T::Struct
        const :custom_list_complexity, T.nilable(Integer)
        const :custom_list_complexity_node_count_exceeding, T.nilable(T::Boolean)
        const :corrected_branch_detection, T.nilable(Integer)
        const :total_node_count_branch_detection, T.nilable(Integer)
        const :corrected_parent_request_count, T.nilable(Integer)

        sig do
          params(
            custom_list_complexity: T.nilable(Integer),
            custom_list_complexity_node_count_exceeding: T.nilable(T::Boolean),
            corrected_branch_detection: T.nilable(Integer),
            total_node_count_branch_detection: T.nilable(Integer),
            corrected_parent_request_count: T.nilable(Integer)
          ).void
        end
        def initialize(custom_list_complexity:, custom_list_complexity_node_count_exceeding:, corrected_branch_detection:, total_node_count_branch_detection:, corrected_parent_request_count:)
          custom_list_complexity = [1, custom_list_complexity.to_i].max if custom_list_complexity
          corrected_branch_detection = [1, corrected_branch_detection.to_i].max if corrected_branch_detection
          super(
            custom_list_complexity: custom_list_complexity,
            custom_list_complexity_node_count_exceeding: custom_list_complexity_node_count_exceeding,
            corrected_branch_detection: corrected_branch_detection,
            total_node_count_branch_detection: total_node_count_branch_detection,
            corrected_parent_request_count: corrected_parent_request_count
          )
        end

        # value can be either a number, boolean or nil
        sig { returns(T::Hash[Symbol, T.nilable(T.any(Integer, T::Boolean))]) }
        def to_hash
          serialize
        end
      end
    end
  end
end
