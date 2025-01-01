# typed: true
# frozen_string_literal: true

require "test_helper"

class ReactGraphqlQueryPreloaderTest < GitHub::TestCase
  include DogstatsTestHelpers

  class TestQuery
    def initialize(query_name)
      @query_name = query_name
    end

    def operation_name
      @query_name
    end

    def context
      @context ||= { query_name: @query_name }
    end
  end

  class TestQueryResponse
    def initialize(data, query_name)
      @data = data
      @query = TestQuery.new(query_name)
    end

    def to_h
      @data
    end

    def query
      @query
    end

    def tracker
      nil
    end
  end

  class TestController < ApplicationController; end

  fixtures do
    @user = create(:user)
  end

  context "#compute_preloaded_queries" do
    test "returns an empty array if there is no match" do
      preloader = setup_preloader_with_request("/randomUrl")
      GitHub.route_query_mapper.stubs(:get_matching_url_pattern).returns(nil)
      assert_nil preloader.compute_preloaded_queries
    end

    test "executes the matched queries" do
      global_id = @user.global_relay_id
      preloader = setup_preloader_with_request("/node/#{global_id}")
      GitHub.route_query_mapper.stubs(:get_matching_url_pattern).returns({
        url: "/node/:id",
        named_captures: {
          id: global_id
        }
      }).once
      GitHub.route_query_mapper.stubs(:fetch).returns(["query_id"]).once

      GitHub.route_query_mapper.stubs(:fetch_variables).returns({ id: "String" }).once

      ApplicationController.any_instance.stubs(:execute_query)
        .returns(TestQueryResponse.new({ data: { node: { id: global_id } } }, "randomQuery")).once
      results = preloader.compute_preloaded_queries
      assert_equal 1, results[:preloaded_queries].length
      assert_equal "query_id", results[:preloaded_queries][0][:queryId]
      assert_equal({ "id" => global_id }, results[:preloaded_queries][0][:variables])
      assert_equal({ data: { node: { id: global_id } } }, results[:preloaded_queries][0][:result])
    end

    test "executes the matched multiple queries" do
      global_id = @user.global_relay_id
      preloader = setup_preloader_with_request("/node/#{global_id}")
      GitHub.route_query_mapper.stubs(:get_matching_url_pattern).returns({
        url: "/node/:id",
        named_captures: {
          id: global_id
        }
      }).once
      first_query_id = "query_id"
      second_query_id = "fff"
      GitHub.route_query_mapper.stubs(:fetch).returns([first_query_id, second_query_id]).once

      GitHub.route_query_mapper.stubs(:fetch_variables).returns({ id: "String" }).twice
      mocked_response = TestQueryResponse.new({ data: { node: { id: global_id } } }, "randomQuery")
      ApplicationController.any_instance.stubs(:execute_query).returns(mocked_response).twice

      results = preloader.compute_preloaded_queries
      assert_equal 2, results[:preloaded_queries].length
      assert_equal first_query_id, results[:preloaded_queries][0][:queryId]
      assert_equal second_query_id, results[:preloaded_queries][1][:queryId]
    end

    test "reports the total execution time" do
      global_id = @user.global_relay_id
      preloader = setup_preloader_with_request("/node/#{global_id}")
      GitHub.route_query_mapper.stubs(:get_matching_url_pattern).returns({
        url: "/node/:id",
        named_captures: {
          id: global_id
        }
      }).once
      GitHub.route_query_mapper.stubs(:fetch).returns(["query_id"]).once

      GitHub.route_query_mapper.stubs(:fetch_variables).returns({ id: "String" }).once
      mocked_response = TestQueryResponse.new({ data: { node: { id: global_id } } }, "randomQuery")

      ApplicationController.any_instance.stubs(:execute_query).returns(mocked_response).once
      tags = [
        "controller:fake",
      ]
      results = preloader.compute_preloaded_queries(variable_overwrite_fns: {}, tags:)
      assert_equal 1, results[:preloaded_queries].length

      assert_dogstats_distribution "request.ssr.preloaded_queries_execution.time", tags: tags
    end

    test "does the correct variable typing" do
      preloader = setup_preloader_with_request("/node/123/myString")

      GitHub.route_query_mapper.stubs(:get_matching_url_pattern).returns({
        url: "/node/:num/:str",
        named_captures: {
          num: "123",
          str: "myString"
        }
      }).once
      GitHub.route_query_mapper.stubs(:fetch).returns(["query_id"]).once
      GitHub.route_query_mapper.stubs(:fetch_variables).returns({ num: "Int", str: "String" }).once
      variables = {
        "num" => 123,
        "str" => "myString"
      }
      mocked_response = TestQueryResponse.new({ data: {} }, "randomQuery")
      ApplicationController.any_instance.stubs(:execute_query).with(
        operation_id: "query_id",
        variables:,
        performance_trace: false,
        scope: nil,
        reporting_tags: [],
        origin: nil,
        run_defer_directive: false,
        is_hard_navigation: false,
        add_query_time_tags_fn: nil
      ).returns(mocked_response).once
      preloader.compute_preloaded_queries
    end

    test "executes the variable overwrite functions" do
      preloader = setup_preloader_with_request("/node/123")

      GitHub.route_query_mapper.stubs(:get_matching_url_pattern).returns({
        url: "/node/:num",
        named_captures: {
          num: 123
        }
      }).once
      GitHub.route_query_mapper.stubs(:fetch).returns(["query_id"]).once
      GitHub.route_query_mapper.stubs(:fetch_variables).returns({ num: "Int" }).once
      variables = {
        "num" => 123
      }
      mocked_response = TestQueryResponse.new({ data: {} }, "randomQuery")
      ApplicationController.any_instance.stubs(:execute_query).with(
        operation_id: "query_id",
        variables:,
        performance_trace: false,
        scope: nil,
        reporting_tags: [],
        origin: nil,
        run_defer_directive: false,
        is_hard_navigation: false,
        add_query_time_tags_fn: nil
      ).returns(mocked_response).once

      variable_overwrite_fns = {
        "/node/:num" => ->(variables) {
          # assert being called
          assert_equal 123, variables[:num]
          variables
        }
      }

      preloader.compute_preloaded_queries(variable_overwrite_fns:)
    end

    test "executes the subscription preload functions" do
      preloader = setup_preloader_with_request("/node/123")

      GitHub.route_query_mapper.stubs(:get_matching_url_pattern).returns({
        url: "/node/:num",
        named_captures: {
          num: 123
        }
      }).once
      GitHub.route_query_mapper.stubs(:fetch).returns(["query_id"]).once
      GitHub.route_query_mapper.stubs(:fetch_variables).returns({ num: "Int" }).once
      variables = {
        "num" => 123
      }
      mock_data = { data: {} }
      mocked_response = TestQueryResponse.new(mock_data, "randomQuery")
      ApplicationController.any_instance.stubs(:execute_query).with(
        operation_id: "query_id",
        variables:,
        performance_trace: false,
        scope: nil,
        reporting_tags: [],
        origin: nil,
        is_hard_navigation: false,
        run_defer_directive: false,
        add_query_time_tags_fn: nil
      ).returns(mocked_response).once

      precompute_subscription_fns = {
        "/node/:num" => ->(query_id, result) {
          # assert being called
          assert_equal "query_id", query_id
          assert_equal mock_data, result
          nil
        }
      }

      preloader.compute_preloaded_queries(precompute_subscription_fns:)
    end
  end

  private

  def setup_preloader_with_request(path, current_user = @user, user_session = @user_session)
    controller = TestController.new
    request = ActionDispatch::TestRequest.create
    request.path = path
    controller.request = request

    ReactGraphql::QueryPreloader.new(
      current_user: current_user,
      request: request,
      controller: controller
    )
  end
end
