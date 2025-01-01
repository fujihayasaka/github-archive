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
    if redacted_item_type?
      serialized_values.insert(index, nil)
    else
      content = T.must(self.content) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      case content
      when DraftIssue
        serialized_values.insert(index, nil)
      when Issue, PullRequest
        serialized_values.insert(index, content.csv_column_value)
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
  # require_prefilled_associations - Whether or not we should raise an exception if we're about to
  #   serialize an association that has not already been prefilled (meaning we're likely to generate
  #   an N+1).
  #
  # Returns csv string representing the value for the given column.
  def special_type_csv_column_value(column, require_prefilled_associations: true, prefilled_associations: nil, redacted_issue_ids: [])
    T.bind(self, MemexProjectItem)

    if require_prefilled_associations
      # We will be moving to ActiveRecord::Core#strict_loading! once https://github.com/rails/rails/pull/55002 is merged.
      #
      # As a result, the following implementation of prefilled association enforcement is for backwards compatibility
      # purposes and was previously delegated to the underlying content model.
      if prefilled_associations
        ensure_preloaded_column_values!
      else
        skip_preloaded_association_requirement = if pull_request?
          # PullRequest items do not support the following columns and their referenced special types.
          column.linked_pull_requests? || column.parent_issue? || column.sub_issues_progress? || column.reviewers?
        elsif issue?
          # Issue items do not support the following columns and their referenced special types.
          column.reviewers?
        else
          false
        end

        issue_for_content&.ensure_preloaded_association!(column) unless skip_preloaded_association_requirement
      end
    end

    field = T.cast(column.to_field, MemexProjectColumn::Interface::SpecialTypeSerializable)
    field.csv_value(self, prefilled_associations:, redacted_issue_ids:)
  end
end
