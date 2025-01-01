# typed: true
# frozen_string_literal: true

module MemexProjectItem::CsvColumnDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { MemexProjectItem }

  # Public: Returns a CSV representation of the item's column values.
  # Unlike `column_values`, this method does not return a hash. Instead, it returns a CSV compatible text representation
  # of the item's column values, used to generate a CSV file for exporting items.
  #
  # columns - Array of MemexProjectColumn for the columns we're trying to get the values for
  # prefilled_associations - MemexProjectItem::PrefilledAssociation
  # redacted_issue_ids - Array of issue ids that are currently redacted.
  #
  # Returns a CSV compatile String, representing the values for the given columns for a MemexProjectItem.
  #
  def csv_column_values(columns:, prefilled_associations: nil, redacted_issue_ids: [])
    serialized_values = columns.map do |column|
      if redacted_item_type? && column.name == MemexProjectColumn::TITLE_COLUMN_NAME
        MemexProjectItem::ColumnDependency::REDACTED_ITEM_TITLE
      elsif redacted_item_type?
        ""
      elsif column.special_type?
        special_type_csv_column_value(
          column,
          prefilled_associations:,
          redacted_issue_ids:
        )
      elsif column.generic_type?
        column_value(
          column,
          prefilled_associations:,
          redacted_issue_ids:,
        )
      end
    end

    index = MemexProjectColumn::CSV_DEFAULT_COLUMN[:index]
    if redacted_item_type?
      serialized_values.insert(index, nil)
    else
      content = T.must(self.content) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      case content
      when DraftIssue
        serialized_values.insert(index, nil)
      when Issue, PullRequest
        serialized_values.insert(index, content.memex_project_column_value.to_csv)
      else
        T.absurd(content)
      end
    end

    serialized_values.to_csv
  end
  alias_method :to_csv, :csv_column_values

  private

  # Retrieves the csv value of the given MemexProjectColumn for this object.
  #
  # The receiver of this method should be a valid `content` association of a MemexProjectItem.
  # This method does `NOT` support tracks or tracked_by columns as they are not supported in Projects Without Limits.
  #
  # column - MemexProjectColumn
  # prefilled_associations - MemexProjectItem::PrefilledAssociations object that, when provided,
  #   will be used to make this method more efficient by using the data contained in this object
  #   and other denormalized data wherever possible. This is required to be passed in for this method.
  #   If you are calling this method from a context where you do not have a `prefilled_associations` object,
  #   you should use `special_type_column_value` instead. if not provided, this method will return nil as column value.
  # redacted_issue_ids - Array of issue ids that are currently redacted.
  #
  # Returns csv string representing the value for the given column.
  def special_type_csv_column_value(column, prefilled_associations: nil, redacted_issue_ids: [])
    T.bind(self, MemexProjectItem)

    field = T.cast(column.to_field, MemexProjectColumn::Interface::SpecialTypeSerializable)
    field.csv_value(self, prefilled_associations:, redacted_issue_ids:)
  end
end
