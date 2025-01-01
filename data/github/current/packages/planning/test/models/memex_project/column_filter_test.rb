# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexProjectColumnFilterTest < GitHub::TestCase
  test "each MemexProjectColumn#data_types has a matching value resolver mapping" do
    # We are skipping tracks and tracked_by for now since it was never implemented for filtering.
    # This may be something we have to come back and check later with use cases.  But for now, this
    # test will at least ensure new data types are added to filter item value resolution support.
    skipped_types    = %w[tracks tracked_by parent_issue sub_issues_progress]
    data_types       = MemexProjectColumn.data_types.keys - skipped_types
    mapped_types     = MemexProject::ColumnFilter::TYPES_TO_VALUE_KEYS.keys.map(&:to_s)
    missing_mappings = data_types - mapped_types

    assert_empty missing_mappings, "Missing value resolver mappings for #{missing_mappings.join(", ")}"
  end
end
