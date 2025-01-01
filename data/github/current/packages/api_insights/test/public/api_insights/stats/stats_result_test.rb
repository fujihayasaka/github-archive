# typed: true
# frozen_string_literal: true

require "test_helper"

module ApiInsights::Stats
  class StatsResultTest < GitHub::TestCase
    test "initialize with only records" do
      result = StatsResult.new(records_dataset)
      assert_equal expected_records, result.records
      assert_equal 2, result.total_record_count
    end

    test "initialize with records and count" do
      result = StatsResult.new(records_with_count_dataset)
      assert_equal expected_records, result.records
      assert_equal 10_000, result.total_record_count
    end

    private

    def records_dataset
      Kusto::Data::Dataset.new [{
        "FrameType" => "DataTable",
        "TableId" => 1,
        "TableName" => "PrimaryResult",
        "TableKind" => "PrimaryResult",
        "Columns" => [
          { "ColumnName" => "column1", "ColumnType" => "string" },
          { "ColumnName" => "column2", "ColumnType" => "string" }
        ],
        "Rows" => [%w[value1 value2], %w[value3 value4]]
      }, {
        "FrameType": "DataTable",
        "TableId": 2,
        "TableKind": "QueryCompletionInformation",
        "TableName": "QueryCompletionInformation",
        "Columns": [{
          "ColumnName": "Timestamp",
          "ColumnType": "datetime"
        }],
        "Rows": [[Time.now.utc]]
      }]
    end

    def records_with_count_dataset
      Kusto::Data::Dataset.new [{
        "FrameType" => "DataTable",
        "TableId" => 1,
        "TableName" => "PrimaryResult",
        "TableKind" => "PrimaryResult",
        "Columns" => [
          { "ColumnName" => "column1", "ColumnType" => "string" },
          { "ColumnName" => "column2", "ColumnType" => "string" }
        ],
        "Rows" => [
          %w[value1 value2],
          %w[value3 value4]
        ]
      }, {
        "FrameType" => "DataTable",
        "TableId" => 2,
        "TableName" => "PrimaryResult",
        "TableKind" => "PrimaryResult",
        "Columns" => [
          { "ColumnName" => "count", "ColumnType" => "long" }
        ],
        "Rows" => [
          [10_000]
        ]
      }, {
        "FrameType": "DataTable",
        "TableId": 2,
        "TableKind": "QueryCompletionInformation",
        "TableName": "QueryCompletionInformation",
        "Columns": [{
          "ColumnName": "Timestamp",
          "ColumnType": "datetime"
        }],
        "Rows": [[Time.now.utc]]
      }]
    end

    def expected_records
      [
        { "column1" => "value1", "column2" => "value2" },
        { "column1" => "value3", "column2" => "value4" }
      ]
    end
  end
end
