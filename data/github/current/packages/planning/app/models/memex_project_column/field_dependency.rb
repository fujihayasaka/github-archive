# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::FieldDependency
  extend ActiveSupport::Concern

  extend T::Helpers
  requires_ancestor { MemexProjectColumn }

  FIELD_CLASS_REGISTRY = T.let(
    %w(
      MemexProjectColumn::Field::Assignees
      MemexProjectColumn::Field::Date
      MemexProjectColumn::Field::IssueType
      MemexProjectColumn::Field::Iteration
      MemexProjectColumn::Field::Labels
      MemexProjectColumn::Field::LinkedPullRequests
      MemexProjectColumn::Field::Milestone
      MemexProjectColumn::Field::Number
      MemexProjectColumn::Field::ParentIssue
      MemexProjectColumn::Field::Repository
      MemexProjectColumn::Field::Reviewers
      MemexProjectColumn::Field::SingleSelect
      MemexProjectColumn::Field::SubIssuesProgress
      MemexProjectColumn::Field::Text
      MemexProjectColumn::Field::Title
      MemexProjectColumn::Field::TrackedBy
      MemexProjectColumn::Field::Tracks
    ),
    T::Array[String]
  )

  class MissingFieldImplementation < StandardError
    sig { params(class_name: T.nilable(T.any(String, Symbol, Exception))).void }
    def initialize(class_name)
      super("Could not find a MemexProjectColumn::Field::Base subclass named #{class_name}")
    end
  end

  sig { returns(String) }
  def field_class_name
    "MemexProjectColumn::Field::#{data_type.camelize}"
  end

  sig { returns(T.nilable(MemexProjectColumn::Field::Base)) }
  def to_field
    return @to_field if defined?(@to_field)
    @to_field = T.let(convert_to_field, T.nilable(MemexProjectColumn::Field::Base))
  end

  sig { returns(T.nilable(T.class_of(MemexProjectColumn::Field::Base))) }
  def to_field_class
    field_class_name.constantize
  rescue NameError
    report_missing_field(field_class_name)
    nil
  end

  sig { returns(T.nilable(MemexProjectColumn::Field::Base)) }
  private def convert_to_field
    return T.cast(self, MemexProjectColumn::Field::Base) if self.class < MemexProjectColumn::Field::Base

    klass = to_field_class
    field = self.becomes(klass) if klass
    return T.cast(field, MemexProjectColumn::Field::Base) if field.class < MemexProjectColumn::Field::Base

    report_missing_field(field_class_name)
    nil
  end

  sig { params(klass: String).void }
  private def report_missing_field(klass)
    exception = MissingFieldImplementation.new(klass)
    raise exception unless Rails.env.production?
    Failbot.report(exception)
  end
end
