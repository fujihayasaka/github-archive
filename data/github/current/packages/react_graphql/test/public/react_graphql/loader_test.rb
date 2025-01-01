# typed: true
# frozen_string_literal: true

require "test_helper"

class ReactGraphql::LoaderTest < GitHub::TestCase
  class FakeController < ApplicationController; end

  class FakePreloadedQueryGqlObject
    attr_reader :query, :tracker
    def initialize(tracker: nil)
      @query = GraphQL::Query.new(Platform::Schema, "query { id }", context: { query_name: "query-1" })
      @tracker = tracker
    end
  end

  class FakeTracker
    class FakeDeferredTracker
      attr_reader :timing_data, :defer_label, :execution_type, :streamed_chunks_count
      def initialize(timing_data:, defer_label:, execution_type:, streamed_chunks_count:)
        @timing_data = timing_data
        @defer_label = defer_label
        @execution_type = execution_type
        @streamed_chunks_count = streamed_chunks_count
      end
    end

    attr_reader :deferred_fragment_trackers
    def initialize(deferred_fragment_trackers)
      @deferred_fragment_trackers = deferred_fragment_trackers.map do |tracker|
        FakeDeferredTracker.new(**tracker)
      end
    end
  end

  class FakeCallbackHandler
    def self.call(query_id, result); end
  end

  context "#preload" do
    test "returns data from compute_preloaded_data" do
      preloaded_data = {
        preloaded_queries: []
      }
      ReactGraphql::QueryPreloader.any_instance.stubs(:compute_preloaded_queries).returns(preloaded_data)
      assert_equal build_loader.preload(ssr_payload: {}), preloaded_data
    end

    context "ssr_payload" do
      test "does not change the payload if there is no preloaded_data" do
        ReactGraphql::QueryPreloader.any_instance.stubs(:compute_preloaded_queries).returns(nil)
        ssr_payload = { data: {} }
        build_loader.preload(ssr_payload: ssr_payload)

        assert_equal ssr_payload, { data: {} }
      end

      test "does not change the payload if there are no preloaded queries" do
        preloaded_data = {
          preloaded_queries: [],
          preloaded_subscriptions: []
        }
        ssr_payload = { data: {} }
        ReactGraphql::QueryPreloader.any_instance.stubs(:compute_preloaded_queries).returns(preloaded_data)
        build_loader.preload(ssr_payload: ssr_payload)

        assert_equal ssr_payload, { data: {} }
      end

      test "updates the ssr_payload with queries and subscriptions removing the timing data" do
        preloaded_queries = [
          {
            query: 1,
            timing_data: {}
          },
          {
            query: 2,
            timing_data: {}
          }
        ]
        preloaded_subscriptions = [1, 2, 3]
        preloaded_data = {
          preloaded_queries: preloaded_queries,
          preloaded_subscriptions: preloaded_subscriptions
        }
        ssr_payload = { data: {} }
        ReactGraphql::QueryPreloader.any_instance.stubs(:compute_preloaded_queries).returns(preloaded_data)

        build_loader.preload(ssr_payload: ssr_payload)

        assert_equal ssr_payload[:data][:payload][:preloadedQueries], [{ query: 1 }, { query: 2 }]
        assert_equal ssr_payload[:data][:payload][:preloadedSubscriptions], preloaded_subscriptions
      end
    end

    context "stats" do
      test "sets the preload_data_duration" do
        stats = {}
        build_loader(stats:).preload(ssr_payload: {})

        refute_nil stats[:preload_data_duration]
      end

      test "sets the query_timings stats" do
        stats = {}
        preloaded_data = {
          preloaded_queries: [
            {
              query: 1,
              timing_data: {
                duration: 1,
              }
            },
            {
              query: 2,
              timing_data: {
                duration: 2
              }
            }
          ],
        }
        ReactGraphql::QueryPreloader.any_instance.stubs(:compute_preloaded_queries).returns(preloaded_data)

        build_loader(stats:).preload(ssr_payload: { data: {} })

        assert_equal stats[:query_timings], [{ duration: 1 }, { duration: 2 }]
      end

      test "does not set the query_timings stats if there is no data" do
        stats = {}
        ReactGraphql::QueryPreloader.any_instance.stubs(:compute_preloaded_queries).returns(nil)

        build_loader(stats:).preload(ssr_payload: { data: {} })

        assert_nil stats[:query_timings]
      end
    end
  end

  context "#compute_deferred_data" do
    test "returns 0 if there is no preloaded_data" do
      assert_equal build_loader.compute_deferred_data(preloaded_data: nil, ssr_payload: {}), 0
    end

    test "loads the deferred data to the preloaded_query result" do
      preloaded_query = {
        result: {
          "data" => {
            foo: "bar"
          }
        }
      }

      preloaded_data = {
        preloaded_queries: [preloaded_query],
        preloaded_query_gql_objects: [FakePreloadedQueryGqlObject.new]
      }

      ReactGraphql::Loader.any_instance.stubs(:execute_deferral_for_query).returns({
        **preloaded_query[:result]["data"],
        deferred_data: "some-data"
      })
      build_loader.compute_deferred_data(preloaded_data: preloaded_data, ssr_payload: { data: { payload: {} } })

      assert_equal preloaded_query[:result]["data"], {
        foo: "bar",
        deferred_data: "some-data"
      }
    end

    context "precompute_subscription_fns" do
      test "preloads subscriptions using provided function if routes match" do
        GitHub.route_query_mapper.stubs(:get_matching_url_pattern).returns({
          url: "some_route"
        })

        preloaded_data = {
          preloaded_queries: [{
            result: {
              "data" => {
                foo: "bar"
              }
            },
            queryId: "deadbeef"
          }],
          preloaded_query_gql_objects: [FakePreloadedQueryGqlObject.new]
        }
        ssr_payload = { data: { payload: {} } }

        build_loader(
          precompute_subscription_fns: {
            "some_route" => ->(id, result) { [id, result] }
          }
        ).compute_deferred_data(preloaded_data: preloaded_data, ssr_payload: ssr_payload)

        expected_result = [
          "deadbeef",
          {
            "data" => {
              foo: "bar"
            }
          }
        ]

        assert_equal ssr_payload[:data][:payload][:preloadedSubscriptions], expected_result
      end

      test "skips subscription preload function if subscriptions are already set" do
        GitHub.route_query_mapper.stubs(:get_matching_url_pattern).returns({
          url: "some_route"
        })

        preloaded_data = {
          preloaded_queries: [{
            result: {
              "data" => {
                foo: "bar"
              }
            },
            queryId: "deadbeef"
          }],
          preloaded_query_gql_objects: [FakePreloadedQueryGqlObject.new]
        }
        preloaded_subscriptions = [1, 2, 3]
        ssr_payload = { data: { payload: { preloadedSubscriptions: preloaded_subscriptions } } }

        FakeCallbackHandler.expects(:call).never

        build_loader(
          precompute_subscription_fns: {
            "some_route" => ->(id, result) { FakeCallbackHandler.call(id, result) }
          }
        ).compute_deferred_data(preloaded_data: preloaded_data, ssr_payload: ssr_payload)

        expected_result = [
          "deadbeef",
          {
            "data" => {
              foo: "bar"
            }
          }
        ]

        assert_equal ssr_payload[:data][:payload][:preloadedSubscriptions], preloaded_subscriptions
      end
    end

    context "query_callback_fns" do
      test "calls query callback function if routes match" do
        GitHub.route_query_mapper.stubs(:get_matching_url_pattern).returns({
          url: "some_route"
        })

        preloaded_data = {
          preloaded_queries: [{
            result: {
              "data" => {
                foo: "bar"
              }
            },
            queryId: "deadbeef"
          }],
          preloaded_query_gql_objects: [FakePreloadedQueryGqlObject.new]
        }

        FakeCallbackHandler.expects(:call).with(
          "deadbeef",
          {
            "data" => {
              foo: "bar"
            }
          }
        ).once

        result = build_loader(
          query_callback_fns: {
            "some_route" => ->(id, result) { FakeCallbackHandler.call(id, result) }
          }
        ).compute_deferred_data(preloaded_data: preloaded_data, ssr_payload: { data: { payload: {} } })

        refute_nil result
      end
    end

    context "trackers" do
      test "does not set tracker if it's nil" do
        preloaded_query = {
          result: {
            "data" => {
              foo: "bar"
            }
          }
        }

        preloaded_data = {
          preloaded_queries: [preloaded_query],
          preloaded_query_gql_objects: [FakePreloadedQueryGqlObject.new]
        }

        loader = build_loader
        loader.compute_deferred_data(preloaded_data: preloaded_data, ssr_payload: { data: { payload: {} } })
        trackers = loader.instance_variable_get(:@trackers) # rubocop:disable GitHub/AvoidDynamicInstanceVariableMethods

        assert_equal trackers, {}
      end

      test "sets tracker based on query_name" do
        preloaded_query = {
          result: {
            "data" => {
              foo: "bar"
            }
          }
        }

        tracker = FakeTracker.new([
          timing_data: {
            duration: 0
          },
          defer_label: "foo",
          execution_type: "bar",
          streamed_chunks_count: 1
        ])

        preloaded_data = {
          preloaded_queries: [preloaded_query],
          preloaded_query_gql_objects: [
            FakePreloadedQueryGqlObject.new(
              tracker: tracker
            )
          ]
        }

        loader = build_loader
        loader.compute_deferred_data(preloaded_data: preloaded_data, ssr_payload: { data: { payload: {} } })
        trackers = loader.instance_variable_get(:@trackers) # rubocop:disable GitHub/AvoidDynamicInstanceVariableMethods

        assert_equal trackers["query-1"], tracker
      end
    end

    context "stats" do
      test "sets query_deferred_timing_data as empty array if there is no data" do
        stats = {}

        assert_equal build_loader(stats:).compute_deferred_data(preloaded_data: nil, ssr_payload: {}), 0
        assert_equal stats[:query_deferred_timing_data], []
      end

      test "does not set defer_data_duration if there is no data" do
        stats = {}

        assert_equal build_loader(stats:).compute_deferred_data(preloaded_data: nil, ssr_payload: {}), 0
        assert_nil stats[:defer_data_duration]
      end

      test "sets defer_data_duration if there is data" do
        stats = {}

        preloaded_data = {
          preloaded_queries: [{
            result: {
              "data" => {
                foo: "bar"
              }
            },
            queryId: "deadbeef"
          }],
          preloaded_query_gql_objects: [FakePreloadedQueryGqlObject.new]
        }

        build_loader(stats:).compute_deferred_data(preloaded_data: T.cast(preloaded_data, T.untyped), ssr_payload: { data: { payload: {} } })
        refute_nil stats[:defer_data_duration]
      end

      test "sets query_deferred_timing_data from tracker info" do
        preloaded_query = {
          result: {
            "data" => {
              foo: "bar"
            }
          }
        }

        tracker = FakeTracker.new([
          timing_data: {
            duration: 0
          },
          defer_label: "foo",
          execution_type: "bar",
          streamed_chunks_count: 1
        ])

        preloaded_data = {
          preloaded_queries: [preloaded_query],
          preloaded_query_gql_objects: [
            FakePreloadedQueryGqlObject.new(
              tracker: tracker
            )
          ]
        }

        stats = {}
        build_loader(stats: stats).compute_deferred_data(preloaded_data: preloaded_data, ssr_payload: { data: { payload: {} } })

        assert_equal stats[:query_deferred_timing_data], [
          {
            :duration => 0,
            "defer_label" => "foo",
            "type" => "bar",
            "streamed_chunks_count" => 1
          }
        ]
      end
    end
  end

  sig do
    params(
      add_query_time_tags_fn: T.nilable(T.proc.params(arg0: String, arg1: T::Hash[T.untyped, T.untyped]).returns(T.nilable(T::Array[String]))),
      origin: T.untyped,
      path_override: T.nilable(String),
      precompute_subscription_fns: T::Hash[String, T.proc.params(arg0: T.untyped, arg1: T.untyped).returns(T.untyped)],
      query_callback_fns: T::Hash[String, T.proc.params(arg0: T.untyped, arg1: T.untyped).returns(T.untyped)],
      request: ActionDispatch::Request,
      run_async_with_defer: T::Boolean,
      stats: T::Hash[Symbol, T.untyped],
      tags: T::Array[String],
      user: T.nilable(User),
      variable_overwrite_fns: T::Hash[Symbol, T.proc.params(path_variables: T::Hash[T.untyped, T.untyped]).returns(T.untyped)]
    ).returns(ReactGraphql::Loader)
  end
  def build_loader(
    add_query_time_tags_fn: nil,
    origin: nil,
    path_override: nil,
    precompute_subscription_fns: {},
    query_callback_fns: {},
    request: ActionDispatch::Request.new({}),
    run_async_with_defer: false,
    stats: {},
    tags: [],
    user: nil,
    variable_overwrite_fns: {}
  )
    ReactGraphql::Loader.new(
      add_query_time_tags_fn:,
      controller: FakeController.new,
      origin:,
      path_override:,
      precompute_subscription_fns:,
      query_callback_fns:,
      request:,
      run_async_with_defer:,
      stats:,
      tags:,
      user:,
      variable_overwrite_fns:
    )
  end
end
