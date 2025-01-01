# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Interface::Indexable
  module Processor
    class IssueUpdateIssueFieldNumberValue < IssueUpdateIssueFieldValue
      sig { override.returns(T.class_of(MemexProjectColumn::Field::IssueField::Base)) }
      private def field_class
        MemexProjectColumn::Field::IssueField::Number
      end
    end
  end
end
