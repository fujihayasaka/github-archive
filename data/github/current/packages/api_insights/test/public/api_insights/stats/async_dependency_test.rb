# typed: true
# frozen_string_literal: true

require "test_helper"

module ApiInsights::Stats
  class AsyncDependencyTest < GitHub::TestCase
    fixtures do
      @user = create(:user)
    end

    setup do
      @object = Object.new
      @object.extend(ApiInsights::Stats::AsyncDependency)
      # note that stubbed data may not fully match actual results
      @requestor_has_activity = { "subject_id" => 1, "subject_name" => "monalisa" }
      @summary_stats = Kusto::Data::Dataset.new [{
        "FrameType" => "DataTable",
        "TableId" => 1,
        "TableName" => "PrimaryResult",
        "TableKind" => "PrimaryResult",
        "Columns" => [
          { "ColumnName" => "total_request_count", "ColumnType" => "int" },
          { "ColumnName" => "rate_limited_request_count", "ColumnType" => "int" },
        ],
        "Rows" => [[6000, 1234]]
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

      @time_stats = Kusto::Data::Dataset.new [{
        "FrameType" => "DataTable",
        "TableId" => 1,
        "TableName" => "PrimaryResult",
        "TableKind" => "PrimaryResult",
        "Columns" => [
          { "ColumnName" => "timestamp", "ColumnType" => "int" },
          { "ColumnName" => "total_request_count", "ColumnType" => "int" },
          { "ColumnName" => "rate_limited_request_count", "ColumnType" => "int" },
        ],
        "Rows" => [[123456, 6000, 1234]]
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

      @subject_stats = Kusto::Data::Dataset.new [{
        "FrameType" => "DataTable",
        "TableId" => 1,
        "TableName" => "PrimaryResult",
        "TableKind" => "PrimaryResult",
        "Columns" => [
          { "ColumnName" => "subject_id", "ColumnType" => "int" },
          { "ColumnName" => "subject_name", "ColumnType" => "string" },
          { "ColumnName" => "total_request_count", "ColumnType" => "int" },
          { "ColumnName" => "rate_limited_request_count", "ColumnType" => "int" },
        ],
        "Rows" => [[5, "subject", 6000, 1234]]
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

    context "futures" do
      test "async_requestor_has_activity async" do
        ApiInsights::Stats::RequestorHasActivity.any_instance.stubs(:get).returns(@requestor_has_activity)
        future = @object.async_requestor_has_activity(organization_id: 1234, user_id: 1)
        refute_nil future.value
        assert future.is_a?(Concurrent::Promises::Future)
        assert_equal 1, future.value["subject_id"]
        assert_equal "monalisa", future.value["subject_name"]
      end

      test "async_requestor_has_activity async error" do
        error = StandardError.new("Boom!")
        ApiInsights::Stats::RequestorHasActivity.any_instance.stubs(:get).raises(error)
        future = @object.async_requestor_has_activity(organization_id: 1234, user_id: 1)
        assert future.is_a?(Concurrent::Promises::Future)
        assert_nil future.value
        assert_equal error, future.reason
      end

      test "async_summary_stats async" do
        ApiInsights::Stats::StatsBase.any_instance.stubs(:get).returns(::ApiInsights::Stats::StatsResult.new(@summary_stats))
        future = @object.async_summary_stats(min: Time.now - 1.day, max: Time.now, organization_id: 1234)
        refute_nil future.value
        assert future.is_a?(Concurrent::Promises::Future)
        assert_equal 6000, future.value.records.first["total_request_count"]
        assert_equal 1234, future.value.records.first["rate_limited_request_count"]
      end

      test "async_summary_stats async error" do
        error = StandardError.new("Boom!")
        ApiInsights::Stats::StatsBase.any_instance.stubs(:get).raises(error)
        future = @object.async_summary_stats(min: Time.now - 1.day, max: Time.now, organization_id: 1234)
        assert future.is_a?(Concurrent::Promises::Future)
        assert_nil future.value
        assert_equal error, future.reason
      end

      test "async_installation_summary_stats async" do
        ApiInsights::Stats::StatsBase.any_instance.stubs(:get).returns(::ApiInsights::Stats::StatsResult.new(@summary_stats))
        future = @object.async_installation_summary_stats(min: Time.now - 1.day, max: Time.now, organization_id: 1, installation_id: 2)
        assert future.is_a?(Concurrent::Promises::Future)
        assert_equal 6000, future.value.records.first["total_request_count"]
        assert_equal 1234, future.value.records.first["rate_limited_request_count"]
      end

      test "async_installation_summary_stats async error" do
        error = StandardError.new("Boom!")
        ApiInsights::Stats::StatsBase.any_instance.stubs(:get).raises(error)
        future = @object.async_installation_summary_stats(min: Time.now - 1.day, max: Time.now, organization_id: 1, installation_id: 2)
        assert future.is_a?(Concurrent::Promises::Future)
        assert_nil future.value
        assert_equal error, future.reason
      end

      test "async_user_summary_stats async" do
        ApiInsights::Stats::StatsBase.any_instance.stubs(:get).returns(::ApiInsights::Stats::StatsResult.new(@summary_stats))
        future = @object.async_user_summary_stats(min: Time.now - 1.day, max: Time.now, organization_id: 1, user_id: 2)
        assert future.is_a?(Concurrent::Promises::Future)
        assert_equal 6000, future.value.records.first["total_request_count"]
        assert_equal 1234, future.value.records.first["rate_limited_request_count"]
      end

      test "async_user_summary_stats async error" do
        error = StandardError.new("Boom!")
        ApiInsights::Stats::StatsBase.any_instance.stubs(:get).raises(error)
        future = @object.async_user_summary_stats(min: Time.now - 1.day, max: Time.now, organization_id: 1, user_id: 2)
        assert future.is_a?(Concurrent::Promises::Future)
        assert_nil future.value
        assert_equal error, future.reason
      end

      test "async_actor_summary_stats async" do
        ApiInsights::Stats::StatsBase.any_instance.stubs(:get).returns(::ApiInsights::Stats::StatsResult.new(@summary_stats))
        future = @object.async_actor_summary_stats(
          min: Time.now - 1.day,
          max: Time.now,
          organization_id: 1,
          actor_id: 2,
          actor_type: ::ApiInsights::Stats::ActorType::OauthApp
        )
        assert future.is_a?(Concurrent::Promises::Future)
        assert_equal 6000, future.value.records.first["total_request_count"]
        assert_equal 1234, future.value.records.first["rate_limited_request_count"]
      end

      test "async_actor_summary_stats async error" do
        error = StandardError.new("Boom!")
        ApiInsights::Stats::StatsBase.any_instance.stubs(:get).raises(error)
        future = @object.async_actor_summary_stats(
          min: Time.now - 1.day,
          max: Time.now,
          organization_id: 1,
          actor_id: 2,
          actor_type: ::ApiInsights::Stats::ActorType::OauthApp
        )
        assert future.is_a?(Concurrent::Promises::Future)
        assert_nil future.value
        assert_equal error, future.reason
      end

      test "async_summary_time_stats async" do
        ApiInsights::Stats::StatsBase.any_instance.stubs(:get).returns(::ApiInsights::Stats::StatsResult.new(@time_stats))
        future = @object.async_summary_time_stats(
          min: Time.now - 1.day,
          max: Time.now,
          organization_id: 1,
          timestamp_increment: "30m",
        )
        assert future.is_a?(Concurrent::Promises::Future)
        assert_equal 123456, future.value.records.first["timestamp"]
        assert_equal 6000, future.value.records.first["total_request_count"]
        assert_equal 1234, future.value.records.first["rate_limited_request_count"]
      end

      test "async_summary_time_stats async error" do
        error = StandardError.new("Boom!")
        ApiInsights::Stats::StatsBase.any_instance.stubs(:get).raises(error)
        future = @object.async_summary_time_stats(
          min: Time.now - 1.day,
          max: Time.now,
          organization_id: 1,
          timestamp_increment: "30m"
        )
        assert future.is_a?(Concurrent::Promises::Future)
        assert_nil future.value
        assert_equal error, future.reason
      end

      test "async_installation_time_stats async" do
        ApiInsights::Stats::StatsBase.any_instance.stubs(:get).returns(::ApiInsights::Stats::StatsResult.new(@time_stats))
        future = @object.async_installation_time_stats(
          min: Time.now - 1.day,
          max: Time.now,
          organization_id: 1,
          timestamp_increment: "30m",
          installation_id: 1,
        )
        assert future.is_a?(Concurrent::Promises::Future)
        assert_equal 123456, future.value.records.first["timestamp"]
        assert_equal 6000, future.value.records.first["total_request_count"]
        assert_equal 1234, future.value.records.first["rate_limited_request_count"]
      end

      test "async_installation_time_stats async error" do
        error = StandardError.new("Boom!")
        ApiInsights::Stats::StatsBase.any_instance.stubs(:get).raises(error)
        future = @object.async_installation_time_stats(
          min: Time.now - 1.day,
          max: Time.now,
          organization_id: 1,
          installation_id: 1,
          timestamp_increment: "30m"
        )
        assert future.is_a?(Concurrent::Promises::Future)
        assert_nil future.value
        assert_equal error, future.reason
      end

      test "async_user_time_stats async" do
        ApiInsights::Stats::StatsBase.any_instance.stubs(:get).returns(::ApiInsights::Stats::StatsResult.new(@time_stats))
        future = @object.async_user_time_stats(
          min: Time.now - 1.day,
          max: Time.now,
          organization_id: 1,
          timestamp_increment: "30m",
          user_id: 1,
        )
        assert future.is_a?(Concurrent::Promises::Future)
        assert_equal 123456, future.value.records.first["timestamp"]
        assert_equal 6000, future.value.records.first["total_request_count"]
        assert_equal 1234, future.value.records.first["rate_limited_request_count"]
      end

      test "async_user_time_stats async error" do
        error = StandardError.new("Boom!")
        ApiInsights::Stats::StatsBase.any_instance.stubs(:get).raises(error)
        future = @object.async_user_time_stats(
          min: Time.now - 1.day,
          max: Time.now,
          organization_id: 1,
          user_id: 1,
          timestamp_increment: "30m"
        )
        assert future.is_a?(Concurrent::Promises::Future)
        assert_nil future.value
        assert_equal error, future.reason
      end

      test "async_actor_time_stats async" do
        ApiInsights::Stats::StatsBase.any_instance.stubs(:get).returns(::ApiInsights::Stats::StatsResult.new(@time_stats))
        future = @object.async_actor_time_stats(
          min: Time.now - 1.day,
          max: Time.now,
          organization_id: 1,
          timestamp_increment: "30m",
          actor_id: 1,
          actor_type: ::ApiInsights::Stats::ActorType::OauthApp,
        )
        assert future.is_a?(Concurrent::Promises::Future)
        assert_equal 123456, future.value.records.first["timestamp"]
        assert_equal 6000, future.value.records.first["total_request_count"]
        assert_equal 1234, future.value.records.first["rate_limited_request_count"]
      end

      test "async_actor_time_stats async error" do
        error = StandardError.new("Boom!")
        ApiInsights::Stats::StatsBase.any_instance.stubs(:get).raises(error)
        future = @object.async_actor_time_stats(
          min: Time.now - 1.day,
          max: Time.now,
          organization_id: 1,
          actor_id: 1,
          actor_type: ::ApiInsights::Stats::ActorType::OauthApp,
          timestamp_increment: "30m"
        )
        assert future.is_a?(Concurrent::Promises::Future)
        assert_nil future.value
        assert_equal error, future.reason
      end

      test "async_summary_subject_stats async" do
        ApiInsights::Stats::StatsBase.any_instance.stubs(:get).returns(::ApiInsights::Stats::StatsResult.new(@subject_stats))
        future = @object.async_summary_subject_stats(
          organization_id: 1,
          min: Time.now - 1.day,
          max: Time.now,
          sorts: [],
          page: 1,
          per_page: 10,
        )
        assert future.is_a?(Concurrent::Promises::Future)
        assert_equal 5, future.value.records.first["subject_id"]
        assert_equal "subject", future.value.records.first["subject_name"]
        assert_equal 6000, future.value.records.first["total_request_count"]
        assert_equal 1234, future.value.records.first["rate_limited_request_count"]
      end

      test "async_summary_subject_stats async error" do
        error = StandardError.new("Boom!")
        ApiInsights::Stats::StatsBase.any_instance.stubs(:get).raises(error)
        future = @object.async_summary_subject_stats(
          organization_id: 1,
          min: Time.now - 1.day,
          max: Time.now,
          sorts: [],
          page: 1,
          per_page: 10,
        )
        assert future.is_a?(Concurrent::Promises::Future)
        assert_nil future.value
        assert_equal error, future.reason
      end

      test "async_route_installation_stats async" do
        ApiInsights::Stats::StatsBase.any_instance.stubs(:get).returns(::ApiInsights::Stats::StatsResult.new(@subject_stats))
        future = @object.async_route_installation_stats(
          organization_id: 1,
          installation_id: 2,
          min: Time.now - 1.day,
          max: Time.now,
          sorts: [],
          page: 1,
          per_page: 10,
        )
        assert future.is_a?(Concurrent::Promises::Future)
        assert_equal 5, future.value.records.first["subject_id"]
        assert_equal "subject", future.value.records.first["subject_name"]
        assert_equal 6000, future.value.records.first["total_request_count"]
        assert_equal 1234, future.value.records.first["rate_limited_request_count"]
      end

      test "async_route_installation_stats async error" do
        error = StandardError.new("Boom!")
        ApiInsights::Stats::StatsBase.any_instance.stubs(:get).raises(error)
        future = @object.async_route_installation_stats(
          organization_id: 1,
          installation_id: 2,
          min: Time.now - 1.day,
          max: Time.now,
          sorts: [],
          page: 1,
          per_page: 10,
        )
        assert future.is_a?(Concurrent::Promises::Future)
        assert_nil future.value
        assert_equal error, future.reason
      end

      test "async_actor_route_installation_stats async" do
        ApiInsights::Stats::StatsBase.any_instance.stubs(:get).returns(::ApiInsights::Stats::StatsResult.new(@subject_stats))
        future = @object.async_actor_route_installation_stats(
          organization_id: 1,
          actor_id: 2,
          actor_type: ::ApiInsights::Stats::ActorType::OauthApp,
          min: Time.now - 1.day,
          max: Time.now,
          sorts: [],
          page: 1,
          per_page: 10,
        )
        assert future.is_a?(Concurrent::Promises::Future)
        assert_equal 5, future.value.records.first["subject_id"]
        assert_equal "subject", future.value.records.first["subject_name"]
        assert_equal 6000, future.value.records.first["total_request_count"]
        assert_equal 1234, future.value.records.first["rate_limited_request_count"]
      end

      test "async_actor_route_installation_stats async error" do
        error = StandardError.new("Boom!")
        ApiInsights::Stats::StatsBase.any_instance.stubs(:get).raises(error)
        future = @object.async_actor_route_installation_stats(
          organization_id: 1,
          actor_id: 2,
          actor_type: ::ApiInsights::Stats::ActorType::OauthApp,
          min: Time.now - 1.day,
          max: Time.now,
          sorts: [],
          page: 1,
          per_page: 10
        )
        assert future.is_a?(Concurrent::Promises::Future)
        assert_nil future.value
        assert_equal error, future.reason
      end

      test "async_user_stats async" do
        ApiInsights::Stats::StatsBase.any_instance.stubs(:get).returns(::ApiInsights::Stats::StatsResult.new(@subject_stats))
        future = @object.async_user_stats(
          organization_id: 1,
          user_id: 2,
          min: Time.now - 1.day,
          max: Time.now,
          sorts: [],
          page: 1,
          per_page: 10,
        )
        assert future.is_a?(Concurrent::Promises::Future)
        assert_equal 5, future.value.records.first["subject_id"]
        assert_equal "subject", future.value.records.first["subject_name"]
        assert_equal 6000, future.value.records.first["total_request_count"]
        assert_equal 1234, future.value.records.first["rate_limited_request_count"]
      end

      test "async_user_stats async error" do
        error = StandardError.new("Boom!")
        ApiInsights::Stats::StatsBase.any_instance.stubs(:get).raises(error)
        future = @object.async_user_stats(
          organization_id: 1,
          user_id: 2,
          min: Time.now - 1.day,
          max: Time.now,
          sorts: [],
          page: 1,
          per_page: 10
        )
        assert future.is_a?(Concurrent::Promises::Future)
        assert_nil future.value
        assert_equal error, future.reason
      end
    end
  end
end
