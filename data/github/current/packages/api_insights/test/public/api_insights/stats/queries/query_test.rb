# typed: true
# frozen_string_literal: true

require "test_helper"

module ApiInsights::Stats::Queries
  class QueryTest < GitHub::TestCase
    def setup
      @table_name = "materialized_view(\"APIINSIGHTS_stats_v1\")"

      @filter = mock
      @filter.stubs(:to_s).returns("filter_expression")
      @filter.stubs(:parameters).returns({ "filter_param" => "value" })

      @summary_field = mock
      @summary_field.stubs(:to_s).returns("summary_expression")

      @summary_key_field = mock
      @summary_key_field.stubs(:to_s).returns("summary_key_expression")

      @sort_definition = mock
      @sort_definition.stubs(:to_s).returns("sort_expression")

      @pager = mock
      @pager.stubs(:to_s).returns("pager_expression")
      @pager.stubs(:parameters).returns({ "pager_param" => "value" })

      @timestamp_increment_summary_key = mock
      @timestamp_increment_summary_key.stubs(:to_s).returns("timestamp_key_expression")
      @timestamp_increment_summary_key.stubs(:parameters).returns({ "timestamp_param" => "value" })
    end

    context "initialize" do
      test "raises error when tabular_input is empty" do
        error = assert_raises(RuntimeError) { Query.new("") }
        assert_equal("tabular_input cannot be empty", error.message)
      end

      test "initializes with valid tabular_input" do
        query = Query.new("valid_input")
        assert_equal("valid_input", query.tabular_input)
        assert_empty(query.filters)
        assert_empty(query.summary_fields)
        assert_empty(query.summary_key_fields)
        assert_empty(query.summary_filters)
        assert_empty(query.sort_definitions)
        assert_nil(query.timestamp_increment_summary_key)
        assert_nil(query.pager)
      end
    end

    context "text" do
      test "raises error when filters are missing" do
        query = Query.new @table_name
        query.summary_fields << @summary_field
        query.sort_definitions << @sort_definition
        error = assert_raises(Error) { query.text }
        assert_equal(ErrorCode::FILTERS_NOT_SPECIFIED, error.code)
      end

      test "raises error when summary fields are missing" do
        query = Query.new @table_name
        query.filters << @filter
        query.sort_definitions << @sort_definition
        error = assert_raises(Error) { query.text }
        assert_equal(ErrorCode::SUMMARY_FIELDS_NOT_SPECIFIED, error.code)
      end

      test "raises error when sort definitions are missing and pager is present" do
        query = Query.new @table_name
        query.filters << @filter
        query.summary_fields << @summary_field
        query.pager = @pager
        error = assert_raises(Error) { query.text }
        assert_equal(ErrorCode::SORT_DEFINITIONS_NOT_SPECIFIED_WHEN_PAGING, error.code)
      end

      test "returns correct query text when all required fields are present" do
        query = Query.new @table_name
        query.filters << @filter
        query.summary_fields << @summary_field
        query.sort_definitions << @sort_definition
        expected_text = <<~KQL
          materialized_view("APIINSIGHTS_stats_v1")
          | where
              filter_expression
          | summarize
              summary_expression
          | sort by
              sort_expression
          KQL
        assert_equal expected_text, query.text
      end

      test "includes summary keys when present" do
        query = Query.new @table_name
        query.filters << @filter
        query.summary_fields << @summary_field
        query.sort_definitions << @sort_definition
        query.summary_key_fields << @summary_key_field
        expected_text = <<~KQL
          materialized_view("APIINSIGHTS_stats_v1")
          | where
              filter_expression
          | summarize
              summary_expression
              by
              summary_key_expression
          | sort by
              sort_expression
          KQL
        assert_equal expected_text, query.text
      end

      test "includes summary filters when present" do
        query = Query.new @table_name
        query.filters << @filter
        query.summary_fields << @summary_field
        query.sort_definitions << @sort_definition
        query.summary_filters << @filter
        expected_text = <<~KQL
          materialized_view("APIINSIGHTS_stats_v1")
          | where
              filter_expression
          | summarize
              summary_expression
          | where
              filter_expression
          | sort by
              sort_expression
        KQL
        assert_equal expected_text, query.text
      end

      test "includes pager when present" do
        query = Query.new @table_name
        query.filters << @filter
        query.summary_fields << @summary_field
        query.sort_definitions << @sort_definition
        query.pager = @pager
        expected_text = <<~KQL
          let results = materialize(
          materialized_view("APIINSIGHTS_stats_v1")
          | where
              filter_expression
          | summarize
              summary_expression
          | sort by
              sort_expression
          );
          results | where pager_expression;
          results | count
        KQL
        assert_equal expected_text, query.text
      end
    end

    context "parameters" do
      test "returns empty parameters when no components are present" do
        query = Query.new @table_name
        assert_equal({}, query.parameters)
      end

      test "returns filter parameters when filters are present" do
        query = Query.new @table_name
        query.filters << @filter
        expected_parameters = { "filter_param" => "value" }
        assert_equal(expected_parameters, query.parameters)
      end

      test "returns summary filter parameters when summary filters are present" do
        query = Query.new @table_name
        query.summary_filters << @filter
        expected_parameters = { "filter_param" => "value" }
        assert_equal(expected_parameters, query.parameters)
      end

      test "returns timestamp increment summary key parameters when present" do
        query = Query.new @table_name
        query.timestamp_increment_summary_key = @timestamp_increment_summary_key
        expected_parameters = { "timestamp_param" => "value" }
        assert_equal(expected_parameters, query.parameters)
      end

      test "returns pager parameters when pager is present" do
        query = Query.new @table_name
        query.pager = @pager
        expected_parameters = { "pager_param" => "value" }
        assert_equal(expected_parameters, query.parameters)
      end

      test "returns combined parameters when all components are present" do
        query = Query.new @table_name
        query.filters << @filter
        query.summary_filters << @filter
        query.timestamp_increment_summary_key = @timestamp_increment_summary_key
        query.pager = @pager
        expected_parameters = {
          "filter_param" => "value",
          "timestamp_param" => "value",
          "pager_param" => "value"
        }
        assert_equal(expected_parameters, query.parameters)
      end
    end
  end
end
