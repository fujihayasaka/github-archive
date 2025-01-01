# typed: strict
# frozen_string_literal: true

module Elastomer
  module Interfaces
    module Document
      module MemexProjectItem
        class SeedContext < T::Struct
          extend T::Sig

          prop :memex_project_item_id, Integer, default: 1
          prop :content_type, ContentType, default: ContentType::Issue
          prop :users, T::Array[::User], default: []
          prop :milestones, T::Array[::Milestone], default: []
          prop :labels, T::Array[::Label], default: []
          prop :issue_types, T::Array[::IssueType], default: []
          prop :require_non_nil_value, T::Boolean, default: false
          prop :single_select_range, T::Range[Integer], default: (0..3)
          prop :multi_select_range, T::Range[Integer], default: (0..3)
          prop :unindexed_document, T::Hash[T.untyped, T.untyped], default: {}

          sig { returns(T::Boolean) }
          def first_item?
            memex_project_item_id == 1
          end

          sig { returns(Integer) }
          def num_single_select_values
            require_non_nil_value ? 1 : [rand(single_select_range), 1].min
          end

          sig { returns(T::Boolean) }
          def set_value?
            num_single_select_values.positive?
          end

          sig { returns(Integer) }
          def num_multi_select_values
            require_non_nil_value ? [rand(multi_select_range), 1].max : rand(multi_select_range)
          end
        end
      end
    end
  end
end
