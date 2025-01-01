# typed: true
# frozen_string_literal: true

require "test_helper"

module ApiInsights::Stats::Queries
  class SortFieldTest < GitHub::TestCase
    test "all fields covered" do
      summary_fields = SummaryField.values.map(&:to_s)
      summary_key_fields = SummaryKeyField.values.map(&:to_s)
      sort_fields = SortField.values.map(&:to_s)

      all_fields = summary_fields + summary_key_fields

      all_fields.each do |field|
        # Trim field from the first occurrence of `=` to the end of the string and trim trailing whitespace.
        field_without_projection = field.split("=").first&.strip
        assert_includes sort_fields, field_without_projection, "SortField is missing #{field}"
      end
    end
  end
end
