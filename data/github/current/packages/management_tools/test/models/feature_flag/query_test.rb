# typed: true
# frozen_string_literal: true

require "test_helper"

class FeatureFlag::QueryTest < GitHub::TestCase
  context "#query" do
    test "returns the original query" do
      query = "some query"
      result = FeatureFlag::Query.new(query: query)
      assert_equal query, result.query
    end

    test "returns the original query even if it's blank" do
      result = FeatureFlag::Query.new(query: "")
      assert_equal "", result.query
    end
  end

  context "#sort" do
    test "returns a single sort criterion in the correct format" do
      result = FeatureFlag::Query.new(query: "sort:created_at-desc")
      assert_equal "created_at desc", result.sort
    end

    test "returns double sort criteria in the correct format" do
      result = FeatureFlag::Query.new(query: "sort:created_at-desc sort:name-asc")
      assert_equal "created_at desc, name asc", result.sort
    end

    test "allows user to pass in 'rollout' instead of 'rollout_updated_at'" do
      result = FeatureFlag::Query.new(query: "sort:rollout-desc")
      assert_equal "rollout_updated_at desc", result.sort
    end

    test "returns the DEFAULT_SORT if tomfoolery is afoot" do
      result = FeatureFlag::Query.new(query: "sort:foo-desc sort:name-asc")
      assert_equal "rollout_updated_at desc", result.sort
    end

    test "returns the DEFAULT_SORT if no sort criteria provided" do
      result = FeatureFlag::Query.new(query: "")
      assert_equal "rollout_updated_at desc", result.sort
    end
  end

  context "#starts" do
    test "returns the passed in starts criterion" do
      date = "2020-01-01"
      result = FeatureFlag::Query.new(query: "starts:#{date}")
      assert_equal date, result.starts
    end

    test "returns the first passed in starts criterion when passed multiple" do
      date_one = "2020-01-01"
      date_two = "1999-01-01"
      result = FeatureFlag::Query.new(query: "starts:#{date_one} starts:#{date_two}")
      assert_equal date_one, result.starts
    end

    test "returns nil when not passed in starts criterion" do
      result = FeatureFlag::Query.new(query: "")
      assert_nil result.starts
    end
  end

  context "#ends" do
    test "returns the passed in ends criterion" do
      date = "2020-01-01"
      result = FeatureFlag::Query.new(query: "ends:#{date}")
      assert_equal date, result.ends
    end

    test "returns the first passed in ends criterion when passed multiple" do
      date_one = "2020-01-01"
      date_two = "1999-01-01"
      result = FeatureFlag::Query.new(query: "ends:#{date_one} ends:#{date_two}")
      assert_equal date_one, result.ends
    end

    test "returns nil when not passed in ends criterion" do
      result = FeatureFlag::Query.new(query: "")
      assert_nil result.ends
    end
  end

  context "#service" do
    test "returns the passed in service criterion" do
      service = "my_cool_service"
      result = FeatureFlag::Query.new(query: "service:#{service}")
      assert_equal service, result.service
    end

    test "returns a comma separated list of services when passed multiple" do
      service_one = "my_cool_service"
      service_two = "my_very_cool_service"
      result = FeatureFlag::Query.new(query: "service:#{service_one} service:#{service_two}")
      assert_equal "#{service_one},#{service_two}", result.service
    end

    test "returns nil when not passed in service criterion" do
      result = FeatureFlag::Query.new(query: "")
      assert_nil result.service
    end
  end
end
