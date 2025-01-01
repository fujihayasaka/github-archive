# typed: true
# frozen_string_literal: true

require "test_helper"

class ReactSsrRendererTest < GitHub::TestCase
  include DogstatsTestHelpers

  class FakeController < ApplicationController; end

  fixtures do
    @user = create(:user)
  end

  context "#initialize" do
    test "extracts app_name from the ssr_payload" do
      renderer = build_renderer

      assert_equal renderer.instance_variable_get(:@app_name), "react-sandbox"
    end

    context "ssr_args" do
      test "doesn't set ssr_args if ssr is disabled" do
        ssr_args = build_renderer(disable_ssr: true).instance_variable_get(:@ssr_args)

        assert_equal ssr_args, {}
      end

      test "sets the values from ssr_payload" do
        renderer = build_renderer(
          ssr_payload: {
            name: "react-sandbox",
            foo: "bar",
            baz: 1
          }
        )

        ssr_args = renderer.instance_variable_get(:@ssr_args)

        assert_equal ssr_args[:name], "react-sandbox"
        assert_equal ssr_args[:foo], "bar"
        assert_equal ssr_args[:baz], 1
      end

      test "sets the anon value depending if the user is present" do
        ssr_args = build_renderer.instance_variable_get(:@ssr_args)

        assert_equal ssr_args[:anon], true

        ssr_args = build_renderer(user: @user).instance_variable_get(:@ssr_args)

        assert_equal ssr_args[:anon], false
      end

      test "sets tier and colorModes" do
        ssr_args = build_renderer.instance_variable_get(:@ssr_args)

        assert ssr_args[:tier].is_a?(Integer)
        assert_equal ssr_args[:colorModes].keys, [:colorMode, :lightTheme, :darkTheme]
      end

      test "sets clientEnv according to current_user" do
        ssr_args = build_renderer.instance_variable_get(:@ssr_args)
        assert_equal ssr_args[:clientEnv].keys, [:locale, :featureFlags]

        controller = FakeController.new
        controller.instance_variable_set(:@current_user, @user)

        ssr_args = build_renderer(controller: controller).instance_variable_get(:@ssr_args)
        assert_equal ssr_args[:clientEnv].keys, [:locale, :featureFlags, :login]
      end
    end
  end

  context "#render" do
    context "ssr disabled" do
      test "returns 403" do
        build_renderer(disable_ssr: true).render do |ssr_response|
          assert_equal ssr_response.status, 403
          assert_equal ssr_response.success?, false
          assert_empty ssr_response.result
        end
      end

      test "sets stats and reports to datadog" do
        stats = {}
        build_renderer(disable_ssr: true, stats: stats).render {}

        assert_equal stats[:alloy_response_status], 403
        refute_nil stats[:rails_render_duration]
        refute_nil stats[:render_duration]

        assert_dogstats_distribution "react.rails.render_html.time", tags: ["ssr_attempted:false"]
        assert_dogstats_distribution "react.render.html.time", tags: ["ssr_attempted:false"]
      end
    end

    context "ssr enabled" do
      test "calls to Alloy synchronously" do
        Alloy::SyncRenderer
          .any_instance
          .expects(:render)
          .returns(Alloy::Response.new(status: 200, result: "<div>result</div>"))

        stats = {}
        build_renderer(
          force_ssr: true,
          run_async_with_defer: false,
          stats: stats
        ).render do |ssr_response|
          assert_equal ssr_response.status, 200
          assert_equal ssr_response.success?, true
          assert_equal ssr_response.result, "<div>result</div>"
        end

        refute_nil stats[:alloy_render_duration]
        assert_dogstats_distribution "alloy.gh.total.rails.time", tags: ["status:200", "tier:0", "ssr_attempted:true"]
      end

      test "reports unexpected errors and returns 500" do
        Alloy::SyncRenderer
          .any_instance
          .expects(:render)
          .throws("boom")

        stats = {}
        build_renderer(
          force_ssr: true,
          run_async_with_defer: false,
          stats: stats
        ).render do |ssr_response|
          assert_equal ssr_response.status, 500
          assert_equal ssr_response.success?, false
        end

        assert_nil stats[:alloy_render_duration]
        assert_dogstats_increment "alloy.gh.render.error", tags: ["app_name:react-sandbox", "tier:0", "status:500"]
      end

      context "render with defer" do
        test "returns the early error responses" do
          Alloy::AsyncRenderer
            .any_instance
            .expects(:render)
            .returns(ConcurrentFaraday::FutureResponse.new.fulfill(Faraday::Response.new(status: 413, body: "Payload too large")))

          # In case of an early return, we still fetch the deferred queries
          ReactGraphql::Loader
            .any_instance
            .expects(:compute_deferred_data)
            .returns(0)
            .once

          stats = {}
          build_renderer(
            force_ssr: true,
            run_async_with_defer: true,
            stats: stats
          ).render do |ssr_response|
            assert_equal ssr_response.status, 413
            assert_equal ssr_response.success?, false
          end

          refute_nil stats[:alloy_render_duration]
          assert_dogstats_distribution "alloy.gh.total.rails.time", tags: ["status:413", "tier:0", "ssr_attempted:true"]
        end

        test "calls the data loader and waits for the renderer promise" do
          Alloy::AsyncRenderer
            .any_instance
            .expects(:render)
            .returns(
              Promise.resolve(
                Faraday::Response.new(
                  status: 200,
                  body: "<div></div>",
                  response_headers: {
                    "Content-Type" => "text/html",
                    React::SsrRenderer::GITHUB_ALLOY_DURATION_HEADER => 10,
                  }
                )
              )
            )

          ReactGraphql::Loader
            .any_instance
            .expects(:preload)
            .returns({
              preloaded_queries: [1, 2, 3]
            })

          ReactGraphql::Loader
            .any_instance
            .expects(:compute_deferred_data)
            .returns(0)

          stats = {}
          build_renderer(
            force_ssr: true,
            run_async_with_defer: true,
            stats: stats
          ).render do |ssr_response|
            assert_equal ssr_response.status, 200
            assert_equal ssr_response.success?, true
            assert_equal ssr_response.result, "<div></div>"
            assert_equal ssr_response.preloaded_queries, [1, 2, 3]
          end

          refute_nil stats[:alloy_render_duration]
          refute_nil stats[:alloy_wait_duration]
          assert_equal stats[:alloy_duration], 10
          assert_dogstats_distribution "alloy.gh.total.rails.time", tags: ["status:200", "tier:0", "ssr_attempted:true"]
        end
      end

      context "alloy returns an error" do
        test "does not return the error for non-employees and it's not development" do
          request = ActionDispatch::Request.new({})

          Alloy::SyncRenderer
            .any_instance
            .expects(:render)
            .returns(Alloy::Response.new(status: 500, error: "Error"))

          Alloy::ErrorReporter
            .any_instance
            .expects(:report)
            .with(
              error: "Error",
              url: request.url,
              sanitized_url: "",
              user: nil,
              bundler: :webpack
            )

          stats = {}
          build_renderer(
            force_ssr: true,
            run_async_with_defer: false,
            stats: stats,
            request: request
          ).render do |ssr_response|
            assert_equal ssr_response.status, 500
            assert_equal ssr_response.success?, false
            assert_nil ssr_response.error
          end

          assert stats[:alloy_render_error]
        end

        test "returns the error if it's not development" do
          request = ActionDispatch::Request.new({})
          Rails.env.stubs(:development?).returns(true)

          Alloy::SyncRenderer
            .any_instance
            .expects(:render)
            .returns(Alloy::Response.new(status: 500, error: "Error"))

          Alloy::ErrorReporter
            .any_instance
            .expects(:report)
            .with(
              error: "Error",
              url: request.url,
              sanitized_url: "",
              user: nil,
              bundler: :webpack
            )

          stats = {}
          build_renderer(
            force_ssr: true,
            run_async_with_defer: false,
            stats: stats,
            request: request
          ).render do |ssr_response|
            assert_equal ssr_response.status, 500
            assert_equal ssr_response.success?, false
            assert_equal ssr_response.error, "Error"
          end

          assert stats[:alloy_render_error]
        end

        test "returns the error if the user is employee", skip_enterprise: true do
          employee = create(:staff_admin_user)
          request = ActionDispatch::Request.new({})

          Alloy::SyncRenderer
            .any_instance
            .expects(:render)
            .returns(Alloy::Response.new(status: 500, error: "Error"))

          Alloy::ErrorReporter
            .any_instance
            .expects(:report)
            .with(
              error: "Error",
              url: request.url,
              sanitized_url: "",
              user: employee,
              bundler: :webpack
            )

          stats = {}
          build_renderer(
            force_ssr: true,
            run_async_with_defer: false,
            stats: stats,
            request: request,
            user: employee
          ).render do |ssr_response|
            assert_equal ssr_response.status, 500
            assert_equal ssr_response.success?, false
            assert_equal ssr_response.error, "Error"
          end

          assert stats[:alloy_render_error]
        end
      end
    end
  end

  sig do
    params(
      controller: FakeController,
      request: ActionDispatch::Request,
      ssr_payload: T.untyped,
      ssr_hints: Alloy::SelectiveSsr::Hints,
      disable_ssr: T::Boolean,
      force_ssr: T::Boolean,
      user: T.nilable(User),
      add_query_time_tags_fn: T.nilable(T.proc.params(arg0: String, arg1: T::Hash[T.untyped, T.untyped]).returns(T.nilable(T::Array[String]))),
      enabled_flags: T.nilable(T::Array[T.untyped]),
      origin: T.untyped,
      path_override: T.nilable(String),
      precompute_subscription_fns: T::Hash[String, T.proc.params(arg0: T.untyped, arg1: T.untyped).returns(T.untyped)],
      query_callback_fns: T::Hash[String, T.proc.params(arg0: T.untyped, arg1: T.untyped).returns(T.untyped)],
      run_async_with_defer: T::Boolean,
      stats: T::Hash[Symbol, T.untyped],
      tags: T::Array[String],
      variable_overwrite_fns: T::Hash[Symbol, T.proc.params(path_variables: T::Hash[T.untyped, T.untyped]).returns(T.untyped)]
    ).returns(React::SsrRenderer)
  end
  def build_renderer(
    controller: FakeController.new,
    request: ActionDispatch::Request.new({}),
    ssr_payload: {
      name: "react-sandbox"
    },
    ssr_hints: Alloy::SelectiveSsr::Hints.new,
    disable_ssr: false,
    force_ssr: false,
    user: nil,
    add_query_time_tags_fn: nil,
    enabled_flags: [],
    origin: nil,
    path_override: nil,
    precompute_subscription_fns: {},
    query_callback_fns: {},
    run_async_with_defer: false,
    stats: {},
    tags: [],
    variable_overwrite_fns: {}
  )
    controller.request = request

    React::SsrRenderer.new(
      controller: controller,
      request:,
      ssr_payload:,
      ssr_hints:,
      disable_ssr:,
      force_ssr:,
      user:,
      add_query_time_tags_fn:,
      enabled_flags:,
      origin:,
      path_override:,
      precompute_subscription_fns:,
      query_callback_fns:,
      run_async_with_defer:,
      stats:,
      tags:,
      variable_overwrite_fns:
    )
  end
end
