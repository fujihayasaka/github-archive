# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::FieldDependency
  extend ActiveSupport::Concern
  extend T::Sig
  extend T::Helpers
  requires_ancestor { MemexProjectColumn }

  FIELD_CLASS_REGISTRY = T.let(
    %w(
      MemexProjectColumn::Assignees
      MemexProjectColumn::Date
      MemexProjectColumn::IssueType
      MemexProjectColumn::Iteration
      MemexProjectColumn::Labels
      MemexProjectColumn::LinkedPullRequests
      MemexProjectColumn::Milestone
      MemexProjectColumn::Number
      MemexProjectColumn::ParentIssue
      MemexProjectColumn::Repository
      MemexProjectColumn::Reviewers
      MemexProjectColumn::SingleSelect
      MemexProjectColumn::SubIssuesProgress
      MemexProjectColumn::Text
      MemexProjectColumn::Title
      MemexProjectColumn::TrackedBy
      MemexProjectColumn::Tracks
    ),
    T::Array[String]
  )

  class MissingFieldImplementation < StandardError
    extend T::Sig

    sig { params(class_name: T.nilable(T.any(String, Symbol, Exception))).void }
    def initialize(class_name)
      super("Could not find a MemexProjectColumn::Field subclass named #{class_name}")
    end
  end

  sig { returns(T.nilable(MemexProjectColumn::Field)) }
  def to_field
    return @to_field if defined?(@to_field)
    @to_field = T.let(convert_to_field, T.nilable(MemexProjectColumn::Field))
  end

  sig { returns(T.nilable(MemexProjectColumn::Field)) }
  private def convert_to_field
    return T.cast(self, MemexProjectColumn::Field) if self.class < MemexProjectColumn::Field

    field_class_name = "MemexProjectColumn::#{data_type.camelize}"
    field = self.becomes(field_class_name.constantize)
    return T.cast(field, MemexProjectColumn::Field) if field.class < MemexProjectColumn::Field

    # raise the same exception that `constantize` would raise above so that we can share the same error handling code
    raise NameError
  rescue NameError
    exception = MissingFieldImplementation.new(field_class_name)
    raise exception unless Rails.env.production?
    Failbot.report(exception)
    nil
  end
end
