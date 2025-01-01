# typed: true
# frozen_string_literal: true

require "test_helper"

class ReactAppRendererTest < GitHub::TestCase
  include DogstatsTestHelpers

  class FakeReactController < ApplicationController; end

  class FakeController < ApplicationController
    self.react_bundle_name = "app-2"
  end

  fixtures do
    @user = create(:user)
  end

  context "#initialize" do
    context "app_name" do
      test "uses the name being passed" do
        assert_equal build_renderer(app_name: "app").app_name, "app"
      end

      test "uses react_bundle_name" do
        assert_equal build_renderer(controller: FakeController.new).app_name, "app-2"
      end

      test "defaults to the controller name dasherized" do
        assert_equal build_renderer.app_name, "fake-react"
      end
    end

    context "initial_path" do
      test "uses the name being passed" do
        assert_equal build_renderer(path_override: "path").instance_variable_get(:@initial_path), "path"
      end

      test "defaults to the request fullpath" do
        request = ActionDispatch::Request.new({})
        assert_equal build_renderer(request: request).instance_variable_get(:@initial_path), request.fullpath
      end
    end

    context "locals" do
      test "calls the layout_locals_generator" do
        layout_locals_generator = lambda do
          { foo: "bar", baz: 1 }
        end
        assert_equal build_renderer(layout_locals_generator: layout_locals_generator).instance_variable_get(:@locals), { foo: "bar", baz: 1 }
      end

      test "defaults to an empty object" do
        assert_equal build_renderer.instance_variable_get(:@locals), {}
      end
    end

    context "embedded_data" do
      test "calls the payload proc" do
        payload = lambda do
          { foo: "bar", baz: 1 }
        end

        embedded_data = build_renderer(
          payload: payload
        ).instance_variable_get(:@embedded_data)
        assert_equal embedded_data, { payload: { foo: "bar", baz: 1 }, title: nil, appPayload: nil }
      end

      test "sets payload object" do
        payload = { foo: "bar", baz: 1 }

        embedded_data = build_renderer(
          payload: payload
        ).instance_variable_get(:@embedded_data)
        assert_equal embedded_data, { payload: { foo: "bar", baz: 1 }, title: nil, appPayload: nil }
      end

      test "sets title" do
        payload = { foo: "bar", baz: 1 }

        embedded_data = build_renderer(
          payload: payload,
          title: "title"
        ).instance_variable_get(:@embedded_data)
        assert_equal embedded_data, { payload: { foo: "bar", baz: 1 }, title: "title", appPayload: nil }
      end

      test "calls app_payload_generator" do
        payload = { foo: "bar", baz: 1 }
        app_payload_generator = lambda do
          { key: "value" }
        end

        embedded_data = build_renderer(
          payload: payload,
          title: "title",
          app_payload_generator: app_payload_generator
        ).instance_variable_get(:@embedded_data)
        assert_equal embedded_data, { payload: { foo: "bar", baz: 1 }, title: "title", appPayload: { key: "value" } }
      end

      test "adds enabled features to app payload" do
        payload = { foo: "bar", baz: 1 }
        controller = FakeController.new
        controller.request = ActionDispatch::Request.new({})
        disable_feature_flag(:flag)
        controller.add_client_feature_flag([:flag])

        embedded_data = build_renderer(
          payload: payload,
          controller: controller
        ).instance_variable_get(:@embedded_data)
        assert_equal embedded_data, {
          payload: {
            foo: "bar",
            baz: 1
          },
          title: nil,
          appPayload: {
            enabled_features: {
              flag: false
            }
          }
        }
      end

      test "merges app payload from generator and the enabled flags" do
        payload = { foo: "bar", baz: 1 }
        app_payload_generator = lambda do
          { key: "value", enabled_features: { flag_2: true } }
        end

        controller = FakeController.new
        controller.request = ActionDispatch::Request.new({})
        disable_feature_flag(:flag)
        controller.add_client_feature_flag([:flag])

        embedded_data = build_renderer(
          payload: payload,
          controller: controller,
          app_payload_generator: app_payload_generator
        ).instance_variable_get(:@embedded_data)
        assert_equal embedded_data, {
          payload: {
            foo: "bar",
            baz: 1
          },
          title: nil,
          appPayload: {
            key: "value",
            enabled_features: {
              flag: false,
              flag_2: true
            }
          }
        }
      end

      test "adds csrf tokens to payload" do
        payload = { foo: "bar", baz: 1 }
        controller = FakeController.new
        controller.request = ActionDispatch::Request.new({})
        controller.instance_variable_set(:@csrf_tokens, {
          path: {
            method: "deadbeef"
          }
        })

        embedded_data = build_renderer(
          payload: payload,
          controller: controller
        ).instance_variable_get(:@embedded_data)
        assert_equal embedded_data, {
          payload: {
            foo: "bar",
            baz: 1,
            csrf_tokens: {
              path: {
                method: "deadbeef"
              }
            }
          },
          title: nil,
          appPayload: nil
        }
      end
    end
  end

  context "#render" do
    test "calls SsrRenderer and yields response, embedded_data, and attempted_ssr" do
      payload = { foo: "bar", baz: 1 }
      response = Alloy::Response.new(status: 200)
      React::SsrRenderer.any_instance.expects(:render).yields(response, true)

      build_renderer(payload: payload).render do |ssr_response, embedded_data, attempted_ssr|
        assert_equal ssr_response, response
        assert_equal embedded_data, {
          payload: {
            foo: "bar",
            baz: 1
          },
          title: nil,
          appPayload: nil,
        }
        assert_equal attempted_ssr, true
      end
    end

    test "merges preloaded queries into embedded_data" do
      payload = { foo: "bar", baz: 1 }
      preloaded_queries = [{
        queryId: "deadbeef",
        variables: {
          "var" => "value"
        },
        result: {
          "data" => "data"
        }
      }]
      response = Alloy::Response.new(status: 200, preloaded_queries: preloaded_queries)
      React::SsrRenderer.any_instance.expects(:render).yields(response, true)

      build_renderer(payload: payload).render do |ssr_response, embedded_data, attempted_ssr|
        assert_equal ssr_response, response
        assert_equal embedded_data, {
          payload: {
            foo: "bar",
            baz: 1,
            preloadedQueries: preloaded_queries
          },
          title: nil,
          appPayload: nil
        }
        assert_equal attempted_ssr, true
      end
    end
  end

  sig do
    params(
      add_query_time_tags_fn: T.nilable(T.proc.params(arg0: String, arg1: T::Hash[T.untyped, T.untyped]).returns(T.nilable(T::Array[String]))),
      app_name: T.nilable(String),
      app_payload_generator: T.nilable(T.proc.returns(T.nilable(T::Hash[Symbol, T.untyped]))),
      controller: ApplicationController,
      custom_tags: T::Array[String],
      enabled_flags: T.nilable(T::Array[T.untyped]),
      layout_locals_generator: T.nilable(T.proc.returns(T::Hash[Symbol, T.untyped])),
      origin: T.untyped,
      page_data: T::Hash[Symbol, T.untyped],
      path_override: T.nilable(String),
      payload: T.any(T.proc.returns(T::Hash[Symbol, T.untyped]), T::Hash[Symbol, T.untyped]),
      precompute_subscription_fns: T::Hash[String, T.proc.params(arg0: T.untyped, arg1: T.untyped).returns(T.untyped)],
      query_callback_fns: T::Hash[String, T.proc.params(arg0: T.untyped, arg1: T.untyped).returns(T.untyped)],
      request: ActionDispatch::Request,
      ssr_hints: Alloy::SelectiveSsr::Hints,
      disable_ssr: T::Boolean,
      force_ssr: T::Boolean,
      stats: T::Hash[Symbol, T.untyped],
      title: T.nilable(String),
      url_override: T.nilable(String),
      user: T.nilable(User),
      variable_overwrite_fns: T::Hash[Symbol, T.proc.params(path_variables: T::Hash[T.untyped, T.untyped]).returns(T.untyped)],
      run_async_with_defer: T::Boolean,
    ).returns(React::AppRenderer)
  end
  def build_renderer(
    add_query_time_tags_fn: nil,
    app_name: nil,
    app_payload_generator: nil,
    controller: FakeReactController.new,
    custom_tags: [],
    enabled_flags: [],
    layout_locals_generator: nil,
    origin: nil,
    page_data: {},
    path_override: nil,
    payload: {},
    precompute_subscription_fns: {},
    query_callback_fns: {},
    request: ActionDispatch::Request.new({}),
    ssr_hints: Alloy::SelectiveSsr::Hints.new,
    disable_ssr: false,
    force_ssr: false,
    stats: {},
    title: nil,
    url_override: nil,
    user: nil,
    variable_overwrite_fns: {},
    run_async_with_defer: false
  )
    controller.request = request

    React::AppRenderer.new(
      add_query_time_tags_fn:,
      app_name:,
      app_payload_generator:,
      controller:,
      custom_tags:,
      enabled_flags:,
      layout_locals_generator:,
      origin:,
      page_data:,
      path_override:,
      payload:,
      precompute_subscription_fns:,
      query_callback_fns:,
      request:,
      ssr_hints:,
      disable_ssr:,
      force_ssr:,
      stats:,
      title:,
      url_override:,
      user:,
      variable_overwrite_fns:,
      run_async_with_defer:
    )
  end
end
