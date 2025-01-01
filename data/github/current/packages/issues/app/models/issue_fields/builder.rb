# typed: strict
# frozen_string_literal: true

module IssueFields
  class Builder
    # Create multiple issue field values for an issue
    sig do
      params(
        issue: Issue,
        actor: User,
        attributes: T::Array[IssueField::IssueFieldAttributesType]
      ).returns(GH::Result[T::Array[IssueFieldValue]])
    end
    def self.build_issue_field_values(issue:, actor:, attributes:) # rubocop:disable Metrics/MethodLength
      return GH::Result::Ok.new([]) if attributes.empty?

      issue_field_ids = attributes.map(&:field_id)
      issue_fields = IssueField.where(id: issue_field_ids, owner: T.must(issue.repository).owner).index_by(&:id)
      issue_field_values = []

      attributes.each do |field_value|
        field_id = field_value.field_id

        issue_field = issue_fields[field_id]
        unless issue_field
          issue.errors.add(:issue_fields, "Issue field with id #{field_id} not found.")
          return GH::Result::Error::NotFound.new("Issue field with id #{field_id} not found.")
        end

        case field_value
        when Issues::IssueFieldTextValueAttributes
          unless issue_field.data_type_text?
            issue.errors.add(:issue_fields, "Text field value provided for non-text field '#{issue_field.name}'.")
            return GH::Result::Error::Validation.new(issue, message: "Text field value provided for non-text field '#{issue_field.name}'.")
          end

          issue_field_values << update_or_build_text_field_value(
            issue_field: issue_field,
            issue: issue,
            value: field_value.text_value,
            actor: actor
          )
        when Issues::IssueFieldSingleSelectValueAttributes
          unless issue_field.data_type_single_select?
            issue.errors.add(:issue_fields, "Single select field value provided for non-single-select field '#{issue_field.name}'.")
            return GH::Result::Error::Validation.new(issue, message: "Single select field value provided for non-single-select field '#{issue_field.name}'.")
          end

          option = issue_field.options.find { |o| o.id == field_value.option_id }
          unless option
            issue.errors.add(:issue_fields, "Option '#{field_value.option_id}' not found for field '#{issue_field.name}'.")
            return GH::Result::Error::NotFound.new("Option not found for field '#{issue_field.name}'")
          end

          issue_field_values << update_or_build_single_select_field_value(
            issue_field: issue_field,
            issue: issue,
            value: option,
            actor: actor
          )
        when Issues::IssueFieldDateValueAttributes
          unless issue_field.data_type_date?
            issue.errors.add(:issue_fields, "Date field value provided for non-date field '#{issue_field.name}'.")
            return GH::Result::Error::Validation.new(issue, message: "Date field value provided for non-date field '#{issue_field.name}'.")
          end

          begin
            Date.iso8601(field_value.date_value)
          rescue ArgumentError
            issue.errors.add(:issue_fields, "Invalid ISO 8601 date string for field '#{issue_field.name}': #{field_value.date_value.inspect}")
            return GH::Result::Error::Validation.new(issue, message: "Invalid ISO 8601 date string for field '#{issue_field.name}'.")
          end

          issue_field_values << update_or_build_date_field_value(
            issue_field: issue_field,
            issue: issue,
            value: field_value.date_value,
            actor: actor
          )
        when Issues::IssueFieldNumberValueAttributes
          unless issue_field.data_type_number?
            issue.errors.add(:issue_fields, "Number field value provided for non-number field '#{issue_field.name}'.")
            return GH::Result::Error::Validation.new(issue, message: "Number field value provided for non-number field '#{issue_field.name}'.")
          end

          issue_field_values << update_or_build_number_field_value(
            issue_field: issue_field,
            issue: issue,
            value: field_value.number_value,
            actor: actor
          )
        else
          # This is not reachable. T.absurd makes Sorbet complain if we add more types and don't handle them here.
          T.absurd(field_value)
        end
      end

      GH::Result::Ok.new(issue_field_values)
    end

    # Set a text field value for an issue
    sig do
      params(
        issue_field: Issues::IIssueField,
        issue: Issue,
        value: String,
        actor: User
      ).returns(IssueFieldValue)
    end
    def self.update_or_build_text_field_value(issue_field:, issue:, value:, actor:)
      existing = IssueFieldValue.find_by(issue_field: issue_field, issue: issue)
      if existing
        existing.value = value
        existing
      else
        issue_field_value = IssueFieldValue.build(
          issue: issue,
          issue_field: issue_field,
          value: value,
          data_type: "text",
          actor: actor,
          repository: issue.repository
        )
      end
    end

    # Set a single select field value for an issue
    # value should be an IssueFieldOption
    sig do
      params(
        issue_field: Issues::IIssueField,
        issue: Issue,
        value: Issues::IIssueFieldOption,
        actor: User
      ).returns(IssueFieldValue)
    end
    def self.update_or_build_single_select_field_value(issue_field:, issue:, value:, actor:)
      existing = IssueFieldValue.find_by(issue_field: issue_field, issue: issue)
      if existing
        existing.update!(value: value.id)
        existing
      else
        IssueFieldValue.build(
          issue: issue,
          issue_field: issue_field,
          value: value.id,
          data_type: "single_select",
          actor: actor,
          repository: issue.repository
        )
      end
    end

    sig do
      params(
        issue_field: Issues::IIssueField,
        issue: Issue,
        value: String, # ISO 8601 date string
        actor: User
      ).returns(IssueFieldValue)
    end
    def self.update_or_build_date_field_value(issue_field:, issue:, value:, actor:)
      existing = IssueFieldValue.find_by(issue_field: issue_field, issue: issue)
      if existing
        existing.value = value
        existing
      else
        IssueFieldValue.build(
          issue: issue,
          issue_field: issue_field,
          value: value,
          data_type: "date",
          actor: actor,
          repository: issue.repository
        )
      end
    end

    # Set a number field value for an issue
    sig do
      params(
        issue_field: Issues::IIssueField,
        issue: Issue,
        value: Numeric,
        actor: User
      ).returns(IssueFieldValue)
    end
    def self.update_or_build_number_field_value(issue_field:, issue:, value:, actor:)
      existing = IssueFieldValue.find_by(issue_field: issue_field, issue: issue)
      if existing
        existing.value = value
        existing
      else
        issue_field_value = IssueFieldValue.build(
          issue: issue,
          issue_field: issue_field,
          value: value,
          data_type: "number",
          actor: actor,
          repository: issue.repository
        )
      end
    end
  end
end
