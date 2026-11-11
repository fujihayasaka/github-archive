# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Interface::Indexable
  module Processor
    class IssueUpdateIssueFieldMultiSelectValue < IssueUpdateIssueFieldValue
      sig { override.returns(T.class_of(MemexProjectColumn::Field::IssueField::Base)) }
      private def field_class
        MemexProjectColumn::Field::IssueField::MultiSelect
      end

      sig { override.returns(T::Boolean) }
      def valid_message?
        FeatureFlag.vexi.enabled?(:memex_issue_field_multi_select_indexing, default: false) && super
      end
    end
  end
end
