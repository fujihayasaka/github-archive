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
  # require_prefilled_associations - Boolean indicating whether or not prefilled associations should be enforced.
  # prefilled_associations - MemexProjectItem::PrefilledAssociation
  # redacted_issue_ids - Array of issue ids that are currently redacted.
  #
  # Returns a CSV compatile String, representing the values for the given columns for a MemexProjectItem.
  #
  def csv_column_values(columns:, require_prefilled_associations: true, prefilled_associations: nil, redacted_issue_ids: [])
    serialized_values = columns.map do |column|
      if redacted_item_type? && column.name == MemexProjectColumn::TITLE_COLUMN_NAME
        MemexProjectItem::ColumnDependency::REDACTED_ITEM_TITLE
      elsif redacted_item_type?
        ""
      elsif column.special_type?
        special_type_csv_column_value(
          column,
          require_prefilled_associations:,
          prefilled_associations:,
          redacted_issue_ids:
        )
      elsif column.generic_type?
        column_value(
          column,
          require_prefilled_associations:,
          prefilled_associations:,
          redacted_issue_ids:,
        )
      end
    end

    index = MemexProjectColumn::CSV_DEFAULT_COLUMN[:index]
    if draft_issue_type? || redacted_item_type?
      serialized_values.insert(index, nil)
    else
      serialized_values.insert(index, content.csv_column_value)
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
  # require_prefilled_associations - Whether or not we should raise an exception if we're about to
  #   serialize an association that has not already been prefilled (meaning we're likely to generate
  #   an N+1).
  #
  # Returns csv string representing the value for the given column.
  def special_type_csv_column_value(column, require_prefilled_associations: true, prefilled_associations: nil, redacted_issue_ids: [])
    unless prefilled_associations.present?
      return content.memex_special_type_csv_column_value(column, require_prefilled_associations:, redacted_issue_ids:)
    end

    ensure_preloaded_column_values! if require_prefilled_associations
    default_has_many_value = draft_issue? ? nil : []
    data_type = column.data_type.to_sym

    case data_type
    when :assignees
      prefilled_associations
        .assignees(self, default_value: [])
        &.map(&:csv_column_value)&.join(", ")
    when :reviewers
      prefilled_associations
        .reviewers(self, default_value: default_has_many_value)
        &.map { |r| r[:reviewer][:login] }&.join(", ")
    when :labels
      prefilled_associations
        .labels(self, default_value: default_has_many_value)
        &.map(&:csv_column_value)&.join(", ")
    when :linked_pull_requests
      prefilled_associations
        .linked_pull_requests(self, default_value: default_has_many_value)
        &.reject { |pull_request| redacted_issue_ids.include?(pull_request.issue.id) }
        &.map(&:csv_column_value)&.join(", ")
    when :milestone
      milestone = prefilled_associations.milestone(self)
      return unless milestone
      milestone[:title]
    when :repository
      prefilled_associations.repository(self)&.csv_column_value
    when :issue_type
      prefilled_associations.issue_type(self)&.csv_column_value
    when :sub_issues_progress
      prefilled_associations.sub_issues_progress(self)&.csv_column_value
    when :title
      find_preloaded_column_value(column.id)&.value
    when :parent_issue
      parent = prefilled_associations.parent_issue(self)
      return if redacted_issue_ids.include?(parent&.id)
      parent&.csv_column_value
    else
      raise ArgumentError.new("Support for '#{column.data_type}' column has not been implemented")
    end
  end
end
