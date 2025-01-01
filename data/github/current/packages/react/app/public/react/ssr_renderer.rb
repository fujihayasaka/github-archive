# typed: strict
# frozen_string_literal: true

module React
  class SsrRenderer
    GITHUB_ALLOY_DURATION_HEADER = T.let("X-GitHub-Alloy-Duration", String)

    @@error_reporter = T.let(Alloy::ErrorReporter.new, Alloy::ErrorReporter)

    sig do
      params(
        controller: ApplicationController,
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
        variable_overwrite_fns: T::Hash[Symbol, T.proc.params(path_variables: T::Hash[T.untyped, T.untyped]).returns(T.untyped)],
        data_router_enabled: T.nilable(T::Boolean),
      ).void
    end
    def initialize(
      controller:,
      request:,
      ssr_payload:,
      ssr_hints:,
      disable_ssr:,
      force_ssr:,
      user:,
      add_query_time_tags_fn: nil,
      enabled_flags: [],
      origin: nil,
      path_override: nil,
      precompute_subscription_fns: {},
      query_callback_fns: {},
      run_async_with_defer: false,
      stats: {},
      tags: [],
      variable_overwrite_fns: {},
      data_router_enabled: false
    )
      @add_query_time_tags_fn = add_query_time_tags_fn
      @controller = controller
      @helpers = T.let(controller.helpers, T.untyped)
      @enabled_flags = enabled_flags
      @origin = origin
      @path_override = path_override
      @precompute_subscription_fns = precompute_subscription_fns
      @query_callback_fns = query_callback_fns
      @request = request
      @run_async_with_defer = run_async_with_defer
      @ssr_payload = ssr_payload
      @stats = stats
      @tags = tags
      @user = user
      @variable_overwrite_fns = variable_overwrite_fns
      @data_router_enabled = data_router_enabled

      @app_name = T.let(ssr_payload[:name], String)
      @app_actor = T.let(Alloy::AppActor.new(@app_name), Alloy::AppActor)
      @ssr_tier = T.let(Alloy::SelectiveSsr.build(request:, ssr_hints:, disable_ssr:, force_ssr:, user:, app_name: @app_name), Alloy::SelectiveSsr)
      @ssr_enabled = T.let(define_ssr_enabled, T::Boolean)
      @ssr_args = T.let({}, T::Hash[Symbol, T.untyped])

      @tags << "ssr_attempted:#{!!@ssr_enabled}"

      @preloaded_data = T.let(nil, T.nilable(T::Hash[Symbol, T.untyped]))
      @ssr_response = T.let(nil, T.nilable(Alloy::Response))

      if @ssr_enabled
        @data_loader = T.let(build_data_loader, ReactGraphql::Loader)
        @ssr_args = build_ssr_args
        @preloaded_data = @data_loader.preload(ssr_payload: @ssr_payload)
      end
    end

    sig do
      params(
        block: T.proc.params(
          ssr_response: Alloy::Response,
          attempted_ssr: T::Boolean
        ).returns(T.untyped)
      ).returns(T.untyped)
    end
    def render(&block)
      track_react_render_time do
        @ssr_response = if @ssr_enabled
          request_ssr
        else
          Alloy::Response.new(status: 403)
        end

        @stats[:alloy_response_status] = @ssr_response.status

        track_rails_render_time do
          yield @ssr_response, @ssr_enabled
        end
      end
    end

    private

    sig { returns(Alloy::Response) }
    def request_ssr
      status = "unknown"
      timer = Timer.start
      response = if @run_async_with_defer
        request_deferred_ssr
      else
        call_alloy_sync
      end

      status = response.status
      @stats[:alloy_render_duration] = timer.elapsed_ms
      GitHub::TaggingHelper.set_ssr_request_tags(env: @request.env, timing: timer.elapsed_ms)
      handle_expected_alloy_errors(response)

      response
    rescue => e
      status = 500
      GitHub.dogstats.increment("alloy.gh.render.error", tags: ["app_name:#{@app_name}", "status:#{status}", "tier:#{@ssr_tier.tier}"])
      GitHub.logger.error(e, "code.namespace": self.class.name, "code.function": __method__, "app_name": @app_name)
      Alloy::Response.new(status: 500)
    ensure
      alloy_wait_time = @request.env[GitHub::TaggingHelper::ALLOY_WAIT_TIME]
      if alloy_wait_time
        GitHub.dogstats.distribution("alloy.gh.total.rails.time", alloy_wait_time, tags: ["status:#{status}", "tier:#{@ssr_tier.tier}"] + @tags)
      end
    end

    sig { returns(Alloy::Response) }
    def request_deferred_ssr
      defer_and_alloy_timer = Timer.start
      # step 1 kick of the ssr request
      ssr_promise = call_alloy_async

      # step 2 compute all deferred data
      defer_duration = @data_loader.compute_deferred_data(preloaded_data: @preloaded_data, ssr_payload: @ssr_payload)

      # step 3 force for the ssr request to finish
      http_response = ssr_promise.sync

      if http_response.headers
        @stats[:alloy_duration] = http_response.headers[GITHUB_ALLOY_DURATION_HEADER]
        http_response.headers.delete(GITHUB_ALLOY_DURATION_HEADER)
      end

      response = Alloy::Response::from_faraday_response(http_response)
      @stats[:alloy_wait_duration] = defer_and_alloy_timer.elapsed_ms - defer_duration

      # step 4 join the ssr response with the deferred data
      response.preloaded_queries = @preloaded_data[:preloaded_queries] if @preloaded_data.present?
      response
    end

    sig { returns(T.any(ConcurrentFaraday::FutureResponse[T.untyped], Promise[T.untyped])) }
    def call_alloy_async
      ::Alloy::AsyncRenderer.new(
        request: @ssr_args,
        metadata: build_metadata,
      ).render
    end

    sig { returns(Alloy::Response) }
    def call_alloy_sync
      ::Alloy::SyncRenderer.new(
        request: @ssr_args,
        metadata: build_metadata
      ).render
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def build_ssr_args
      {
        **@ssr_payload,
        anon: !@user,
        enableCaching: @app_actor.feature_enabled?(:alloy_enable_caching),
        # TODO: stop using helpers
        clientEnv: @helpers.client_env(app_specific_flags: @enabled_flags),
        tier: @ssr_tier.tier,
        colorModes: {
          colorMode: color_mode.to_s,
          lightTheme: ColorMode.light_theme_for_user(@user, @request).to_s,
          darkTheme: ColorMode.dark_theme_for_user(@user, @request).to_s
        },
        data_router_enabled: @data_router_enabled
      }
    end

    sig { params(response: Alloy::Response).void }
    def handle_expected_alloy_errors(response)
      if response.error.present?
        @stats[:alloy_render_error] = true
        GitHub.dogstats.increment("alloy.gh.render.error", tags: ["app_name:#{@app_name}", "tier:#{@ssr_tier.tier}", "status:#{response.status}"])
        error_reporter.report(
          error: T.must(response.error),
          url: @request.url,
          sanitized_url: sanitized_url,
          user: @user,
          bundler: AssetBundles.get.bundler
        )
      end

      unless @user&.employee? || Rails.env.development?
        response.error = nil
      end
    end

    sig { returns(T.any(ColorMode, String)) }
    def color_mode
      cookie_color_mode = @request.cookies["preferred_color_mode"] || ColorMode.default
      color_mode_with_override = ColorMode.color_mode_with_override(@user, @request)
      return cookie_color_mode if color_mode_with_override.auto?
      color_mode_with_override
    end

    sig { returns(T::Hash[T.any(Symbol, String), T.untyped]) }
    def build_metadata
      metadata = {
        # TODO: stop using helpers
        controller: @helpers.controller_name,
        # TODO: stop using helpers
        action: @helpers.action_name,
        logged_in: !!@user,
        staff: !!@user&.preview_features?,
        catalog_service: GitHub::TaggingHelper.catalog_service(@request.env),
        is_react: true,
        tags: {
          # TODO: stop using helpers
          primer_react_css_modules_ga: feature_enabled?(:primer_react_css_modules_ga)
        }
      }

      referrer_controller_action = GitHub::TaggingHelper.calculate_referrer(@request.env)
      referrer_controller_action.each do |tag|
        (tag_name, tag_value) = tag.split(":")
        metadata[tag_name] = tag_value
      end
      metadata.with_indifferent_access
    end

    sig { returns(T::Boolean) }
    def define_ssr_enabled
      return false if @app_actor.feature_enabled?(:disable_react_ssr)
      return false if feature_enabled?(:disable_react_ssr)

      report_selective_ssr_stats
      @ssr_tier.ssr_enabled?
    end

    sig { void }
    def report_selective_ssr_stats
      GitHub.dogstats.increment(
        "alloy.gh.render.selective_ssr",
        tags: [
          "app_name:#{@app_name}",
          "selective_ssr_result:#{@ssr_tier.ssr_enabled?}",
          "tier:#{@ssr_tier.tier}",
          "logged_in:#{@ssr_tier.metadata.logged_in}",
          "robot:#{@ssr_tier.metadata.robot}",
          "mobile:#{@ssr_tier.metadata.mobile}",
          "spammy:#{@ssr_tier.metadata.spammy}",
          "override:#{@ssr_tier.metadata.override}",
          "highly_cacheable:#{@ssr_tier.hints.highly_cacheable.present?}",
          "no_js_experience:#{@ssr_tier.hints.no_js_experience.present?}",
        ]
      )
    end

    sig { params(block: T.proc.returns(T.untyped)).returns(T.untyped) }
    def track_rails_render_time(&block)
      timer = Timer.start
      yield
    ensure
      GitHub.dogstats.distribution("react.rails.render_html.time", timer.elapsed_ms, tags: @tags)
      @stats[:rails_render_duration] = timer.elapsed_ms
    end

    sig { params(block: T.proc.returns(T.untyped)).returns(T.untyped) }
    def track_react_render_time(&block)
      timer = Timer.start
      block.call
    ensure
      tags = @tags.dup
      tags << "ssr_success:#{@ssr_response&.success?}" if @ssr_enabled
      GitHub.dogstats.distribution("react.render.html.time", timer.elapsed_ms, tags: tags)
      @stats[:render_duration] = timer.elapsed_ms
    end

    sig { returns(T.untyped) }
    def sanitized_url
      # TODO: stop using helpers
      @helpers.analytics_location
    rescue => e # rubocop:todo Lint/GenericRescue
      @request.path
    end

    sig { returns(Alloy::ErrorReporter) }
    def error_reporter
      @@error_reporter
    end

    sig { returns(ReactGraphql::Loader) }
    def build_data_loader
      ReactGraphql::Loader.new(
        add_query_time_tags_fn: @add_query_time_tags_fn,
        controller: @controller,
        origin: @origin,
        path_override: @path_override,
        precompute_subscription_fns: @precompute_subscription_fns,
        query_callback_fns: @query_callback_fns,
        request: @request,
        run_async_with_defer: @run_async_with_defer,
        stats: @stats,
        tags: @tags,
        user: @user,
        variable_overwrite_fns: @variable_overwrite_fns
      )
    end

    sig { params(feature_name: Symbol).returns(T::Boolean) }
    def feature_enabled?(feature_name)
      return GitHub.flipper[feature_name].enabled? if @user.nil?

      @user.feature_enabled?(feature_name)
    end
  end
end
