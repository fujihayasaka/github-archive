# typed: true
# frozen_string_literal: true

require "alloy/renderer"
require "alloy/selective_ssr"
require "alloy/error_reporter"
require "alloy/app_actor"
require "scientist"

module ReactHelper
  extend T::Helpers

  extend ActiveSupport::Concern
  include ColorHelper
  include Platform::Helpers::DeferredQueryHelper
  include UrlSanitizingHelper
  include Scientist
  include ClientEnvHelper

  GITHUB_ALLOY_DURATION_HEADER = T.let("X-GitHub-Alloy-Duration".freeze, String)
  DEFAULT_CPU_BUCKET = "unknown" # Indicates that the browser is not supported or that the cookie is not set

  abstract!

  # Provided by ApplicationController::AuthenticityTokenDependency
  sig { abstract.returns(T.nilable(T::Hash[String, T::Hash[Symbol, T.untyped]])) }
  def csrf_tokens; end

  # Provided by ApplicationController::PersistedGraphqlQueryDependency
  sig { abstract.params(args: T.untyped).returns(T.untyped) }
  def compute_preloaded_queries(**args); end

  sig { abstract.returns(T.nilable(::User)) }
  def current_user; end

  sig { abstract.returns(T.nilable(T::Hash[T.any(String, Symbol), T::Boolean])) }
  def client_feature_flags; end

  module ClassMethods
    sig { returns(T.nilable(String)) }
    attr_accessor :react_bundle_name
  end
  mixes_in_class_methods(ClassMethods)

  sig do
    params(
      payload: T.untyped, # Payload per route used to render the app. It can be either a JSON object or a Proc.
      app_payload_generator: T.untyped, # function generating json payload for the app. This is independent of the route and will only be embedded in the html.
      title: T.nilable(String), # Title of the page, not including the "· GitHub" wordmark suffix.
      page_data: T.untyped, # Page metadata.
      layout: T.any(Symbol, String, FalseClass), # The layout to use.
      stats: T.untyped, # Hash of various stats that can be used for logging purpose.
      turbo: T.nilable(T::Hash[Symbol, String]), # Information about the `turbo-frame` that will wrap the react app.
      ssr: T.nilable(T.any(T::Boolean, Alloy::SSRHints)), # Boolean defaulting to true signaling if the app should be rendered server side.
      status: T.nilable(T.any(Symbol, Integer)), # The HTTP status code to return. Defaults to 200.
      url_override: T.nilable(String),
      path_override: T.nilable(String),
      variable_overwrite_fns: T.untyped,
      precompute_subscription_fns: T.untyped,
      query_callback_fns: T::Hash[String, String], # A map of routes to callback functions to execute after certain queries complete
      custom_tags: T.nilable(T::Array[String]),
      layout_locals_generator: T.nilable(T.proc.returns(T::Hash[Symbol, T.untyped])), # function generating a hash of local variables accessible by the layout. Function must return a hash.
      app_name: T.nilable(String), # The react bundle name. If specified, it will be used instead of class-level `react_bundle_name`
      origin: String, # The origin of the request. Defaults to Platform::ORIGIN_API, override only if authorization happens in another place in the request flow
      run_async_with_defer: T::Boolean, # Boolean defaulting to false signaling if the app should be rendered with the defer directive.
      enabled_flags: T.nilable(T::Array[T.untyped]), # Array passing app specific flags to the client side, needed to do more than basic ff checks aka per user or globally
      add_query_time_tags_fn: T.nilable(T.proc.params(arg0: String, arg1: T::Hash[T.untyped, T.untyped]).returns(T.nilable(T::Array[String])))
    ).returns(T.untyped)
  end
  def render_react_app(
    payload: {},
    app_payload_generator: nil,
    title: nil,
    page_data: {},
    layout: :default,
    stats: {},
    turbo: {},
    ssr: false,
    status: :ok,
    url_override: nil,
    path_override: nil,
    variable_overwrite_fns: {},
    precompute_subscription_fns: {},
    query_callback_fns: {},
    custom_tags: [],
    layout_locals_generator: nil,
    app_name: nil,
    origin: Platform::ORIGIN_API,
    run_async_with_defer: false,
    enabled_flags: [],
    add_query_time_tags_fn: nil
  )
    T.bind(self, T.untyped)
    start_allocated_objects_count = GC.stat(:total_allocated_objects)
    GitHub::TaggingHelper.set_react_tags(env: env)

    respond_to do |format|

      # Note that `format.html` comes *before* `format.json`.
      # This is important. It means it will use HTML, by default, if the Accept header doesn't spell out
      # an obvious preference. E.g. `Accept: */*` will yield HTML. But `Accept: application/json`
      # will yield JSON. A Chrome browsers, as of 2024, sends something
      # like `Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,<BREAK>
      # image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7`.

      format.html do
        render_html(
          payload: payload,
          app_payload_generator: app_payload_generator,
          title: title,
          page_data: page_data,
          layout: layout,
          stats: stats,
          turbo: turbo,
          ssr: ssr,
          status: status,
          url_override: url_override,
          path_override: path_override,
          variable_overwrite_fns: variable_overwrite_fns,
          precompute_subscription_fns: precompute_subscription_fns,
          add_query_time_tags_fn: add_query_time_tags_fn,
          enabled_flags: enabled_flags,
          query_callback_fns: query_callback_fns,
          custom_tags: custom_tags,
          layout_locals_generator: layout_locals_generator,
          app_name: app_name,
          origin: origin,
          run_async_with_defer: run_async_with_defer,
        )
      end

      format.json do
        # if this is a flamegraph request, make sure we include the alloy part
        if flamegraph_mode?(params)
          render_html(
            payload: payload,
            app_payload_generator: app_payload_generator,
            title: title,
            page_data: page_data,
            layout: layout,
            stats: stats,
            turbo: turbo,
            ssr: ssr,
            status: status,
            url_override: url_override,
            path_override: path_override,
            variable_overwrite_fns: variable_overwrite_fns,
            precompute_subscription_fns: precompute_subscription_fns,
            add_query_time_tags_fn: add_query_time_tags_fn,
            query_callback_fns: query_callback_fns,
            enabled_flags: enabled_flags,
            custom_tags: custom_tags,
            layout_locals_generator: layout_locals_generator,
            app_name: app_name,
            origin: origin,
            run_async_with_defer: false,
          )
        else
          T.must(request).env[GitHub::TaggingHelper::PROCESS_REQUEST_REACT_TYPE] = "json"

          res = {
            payload: json_payload(payload),
            title: title
          }

          render json: serialize(res) # rubocop:disable GitHub/RailsViewRenderLiteral
        end
      end
    end
    allocated_objects_count = GC.stat(:total_allocated_objects) - start_allocated_objects_count
    stats[:allocated_objects_count] = allocated_objects_count
  end

  sig do
    params(
      name: String, # Name of the partial. Should match the directory name within react-partials
      props: T.nilable(T::Hash[Symbol, T.untyped]), # props to pass to the partial component
      ssr: T::Boolean, # Boolean defaulting to true signaling if the app should be rendered server side.
      class_name: T.nilable(String), # Additional css class/classes to add to the react-partial element
      origin: T.untyped # the request origin to use in the platform flow
    ).returns(T.untyped)
  end
  def render_react_partial(name: "", props: {}, ssr: false, class_name: nil, origin: nil)
    embedded_data = {
      props: props
    }
    render_with_ssr(
      ssr: ssr,
      ssr_payload: {
        name: name,
        data: embedded_data,
        url: T.must(request).url
      },
      tags: ["partial_name:#{name}"],
      origin: origin
    ) do |ssr_response|
      T.bind(self, T.untyped)
      render partial: "react/partial", locals: {
        name: name,
        attempted_ssr: ssr,
        ssr: ssr_response.success?,
        ssr_error_script_tag: html_safe_json_script_tag(ssr_response.error, "react-partial.ssrError"),
        data_script_tag: html_safe_json_script_tag(serialize(embedded_data), "react-partial.embeddedData"),
        react_root_tag: html_safe_react_root_tag(ssr_response.result, "react-partial.reactRoot"),
        class_name: class_name,
      }
    end
  end

  sig { params(data: T::Hash[T.untyped, T.untyped]).returns(String) }
  def serialize(data)
    GitHub::JSON.dump(data)
  end

  sig { params(data: T.untyped, target: T.untyped).returns(T.nilable(ActiveSupport::SafeBuffer)) }
  def html_safe_json_script_tag(data, target)
    return unless data
    content_tag(
      :script,
      json_escape(data).html_safe, # rubocop:disable Rails/OutputSafety
      type: "application/json",
      data: { target: target }
    )
  end

  sig { params(ssr_result: T.nilable(String), target: String).returns(ActiveSupport::SafeBuffer) }
  def html_safe_react_root_tag(ssr_result, target)
    content_tag(
      :div,
      ssr_result&.html_safe,  # rubocop:disable Rails/OutputSafety
      data: { target: target }
    )
  end

  def ssr_component_async(render_request, custom_tags, stats)
    T.bind(self, T.untyped)
    now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = ::Alloy::AsyncRenderer.render(
      request: render_request,
      metadata: build_metadata,
    )
    timing = Process.clock_gettime(Process::CLOCK_MONOTONIC) - now
    set_ssr_request_tags(timing)

    result
  end

  def handle_expected_alloy_errors(response, stats: {}, render_request: {})
    if response.error.present?
      stats[:alloy_render_error] = true
      GitHub.dogstats.increment("alloy.gh.render.error", tags: ["app_name:#{render_request[:name]}", "tier:#{render_request[:tier]}", "status:#{response.status}"])
      error_reporter.report(
        error: response.error,
        url: T.must(request).url,
        sanitized_url: sanitized_url,
        user: current_user,
        bundler: asset_bundle_helper.asset_bundles.bundler
      )
    end

    unless current_user&.employee? || Rails.env.development?
      response.error = nil
    end
  end

  def ssr_component(render_request, custom_tags, stats)
    status_tag = "status:unknown"
    tier_tag = "tier:#{render_request[:tier]}"
    begin
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      T.bind(self, T.untyped)
      response = ::Alloy::SyncRenderer.render(
        request: render_request,
        metadata: build_metadata
      )
      # since we are not using the async version, we are getting the response directly
      response = T.cast(response, ::Alloy::Response)
      timing = Process.clock_gettime(Process::CLOCK_MONOTONIC) - now
      stats[:alloy_render_duration] = timing

      set_ssr_request_tags(timing)
      handle_expected_alloy_errors(response, stats: stats, render_request: render_request)

      status_tag = "status:#{response.status}"
      response
    rescue => e # rubocop:todo Lint/GenericRescue
      status_tag = "status:500"
      GitHub.dogstats.increment("alloy.gh.render.error", tags: ["app_name:#{render_request[:name]}", status_tag, tier_tag])
      GitHub.logger.error(e, "code.namespace": self.class.name, "code.function": __method__, "app_name": render_request[:name])
      Alloy::Response.new(status: 500)
    ensure
      GitHub.dogstats.distribution("alloy.gh.total.rails.time", T.must(request).env[GitHub::TaggingHelper::ALLOY_WAIT_TIME], tags: [status_tag, tier_tag] + custom_tags)
    end
  end

  sig { params(user: T.nilable(User)).returns(T.any(ColorMode, String)) }
  def color_mode(user)
    cookie_color_mode = T.must(request).cookies["preferred_color_mode"] || ColorMode.default
    color_mode_with_override = color_mode_with_override(user)
    return cookie_color_mode if color_mode_with_override.auto?
    color_mode_with_override
  end

  def cpu_bucket
    T.must(request).cookies["cpu_bucket"] || DEFAULT_CPU_BUCKET
  end

  sig { returns(T::Hash[T.untyped, T.untyped]) }
  def build_metadata
    T.bind(self, T.untyped)
    metadata = {
      controller: controller_name,
      action: action_name,
      logged_in: logged_in?,
      staff: preview_features?,
      catalog_service: GitHub::TaggingHelper.catalog_service(request.env),
      is_react: true,
      tags: {
        primer_react_css_modules_ga: user_or_global_feature_enabled?(:primer_react_css_modules_ga)
      }
    }

    referrer_controller_action = GitHub::TaggingHelper.calculate_referrer(request.env)
    referrer_controller_action.each do |tag|
      (tag_name, tag_value) = tag.split(":")
      metadata[tag_name] = tag_value
    end
    metadata.with_indifferent_access
  end

  private

  sig { params(timing: T.any(Integer, Float)).returns(T.untyped) }
  def set_ssr_request_tags(timing)
    if T.must(request).env[GitHub::TaggingHelper::ALLOY_WAIT_TIME]
      T.must(request).env[GitHub::TaggingHelper::ALLOY_WAIT_TIME] += timing
    else
      T.must(request).env[GitHub::TaggingHelper::ALLOY_WAIT_TIME] = timing
    end

    if T.must(request).env[GitHub::TaggingHelper::ALLOY_CALLS_KEY]
      T.must(request).env[GitHub::TaggingHelper::ALLOY_CALLS_KEY] += 1
    else
      T.must(request).env[GitHub::TaggingHelper::ALLOY_CALLS_KEY] = 1
    end
  end

  sig do
    params(
      payload: T.untyped,
      app_payload_generator: T.untyped,
      title: T.nilable(String),
      page_data: T.untyped,
      layout: T.untyped,
      stats: T.untyped,
      turbo: T.nilable(T::Hash[Symbol, String]),
      ssr: T.untyped,
      status: T.nilable(T.any(Symbol, Integer)),
      url_override: T.nilable(String),
      path_override: T.nilable(String),
      enabled_flags: T.nilable(T::Array[T.untyped]),
      variable_overwrite_fns: T.untyped,
      precompute_subscription_fns: T.untyped,
      add_query_time_tags_fn: T.nilable(T.proc.params(arg0: String, arg1: T::Hash[T.untyped, T.untyped]).returns(T.nilable(T::Array[String]))),
      query_callback_fns: T::Hash[String, T.untyped],
      custom_tags: T.untyped,
      layout_locals_generator: T.nilable(T.proc.returns(T::Hash[Symbol, T.untyped])),
      app_name: T.nilable(String),
      origin: T.untyped,
      run_async_with_defer: T::Boolean,
    ).returns(T.untyped)
  end
  def render_html(
    payload:,
    app_payload_generator:,
    title:,
    page_data:,
    layout:,
    stats:,
    turbo:,
    ssr:,
    status:,
    url_override:,
    path_override:,
    enabled_flags:,
    variable_overwrite_fns:,
    precompute_subscription_fns:,
    add_query_time_tags_fn:,
    query_callback_fns:,
    custom_tags:,
    layout_locals_generator:,
    app_name:,
    origin:,
    run_async_with_defer: false
  )
    lazy = lazy_fetching_enabled? && payload.is_a?(Proc) && !ssr
    render_payload = html_payload(payload, ssr: ssr)

    T.must(request).env[GitHub::TaggingHelper::PROCESS_REQUEST_REACT_TYPE] = "html"
    app_payload = app_payload_generator.call if app_payload_generator
    T.bind(self, T.untyped)
    app_name = app_name || self.class.react_bundle_name || controller_name.dasherize

    unless client_feature_flags.nil?
      app_payload ||= {}
      app_payload[:enabled_features] = client_feature_flags.merge(app_payload[:enabled_features] || {})
    end

    locals = layout_locals_generator&.call || {}

    embedded_data = {
      payload: render_payload,
      title: title,
      appPayload: app_payload
    }

    render_with_ssr(
      ssr: ssr,
      ssr_payload: {
        name: app_name,
        path: path_override || T.must(request).fullpath,
        url: url_override || T.must(request).url,
        data: embedded_data,
      },
      tags: [
        "app_name:#{app_name}",
        "turbo_type:#{turbo_type || "none"}",
      ].concat(custom_tags),
      stats: stats,
      enabled_flags: enabled_flags,
      variable_overwrite_fns: variable_overwrite_fns,
      precompute_subscription_fns: precompute_subscription_fns,
      add_query_time_tags_fn: add_query_time_tags_fn,
      query_callback_fns: query_callback_fns,
      path_override: path_override,
      origin: origin,
      run_async_with_defer: run_async_with_defer,
    ) do |ssr_response|
      embedded_data_with_queries = add_preloaded_queries(embedded_data, ssr_response.preloaded_queries)
      render "react/index", locals: { # rubocop:disable GitHub/RailsViewRenderPathsExist
                                      ssr: ssr_response.success?,
                                      attempted_ssr: ssr,
                                      ssr_error_script_tag: html_safe_json_script_tag(ssr_response.error, "react-app.ssrError"),
                                      data_script_tag: html_safe_json_script_tag(serialize(embedded_data_with_queries), "react-app.embeddedData"),
                                      react_root_tag: html_safe_react_root_tag(ssr_response.result, "react-app.reactRoot"),
                                      payload: payload,
                                      title: title,
                                      page_data: page_data,
                                      javascript_bundle_name: app_name,
                                      turbo: turbo,
                                      initial_path: path_override || T.must(request).fullpath,
                                      lazy: lazy,
                                      layout: layout,
                                      **locals,
      }, layout: layout, status: status
    end
  end

  sig do
    params(
      ssr: T.untyped,
      ssr_payload: T.untyped,
      tags: T.untyped,
      stats: T.untyped,
      variable_overwrite_fns: T.untyped,
      precompute_subscription_fns: T.untyped,
      add_query_time_tags_fn: T.untyped,
      query_callback_fns: T::Hash[String, T.untyped],
      path_override: T.nilable(String),
      origin: T.untyped,
      enabled_flags: T.nilable(T::Array[T.untyped]),
      run_async_with_defer: T.untyped,
      block: T.proc.params(arg0: T.untyped).returns(T.untyped),
    ).returns(T.untyped)
  end
  def render_with_ssr(
    ssr:,
    ssr_payload:,
    tags: [],
    stats: {},
    variable_overwrite_fns: {},
    precompute_subscription_fns: {},
    add_query_time_tags_fn: nil,
    query_callback_fns: {},
    path_override: nil,
    origin: nil,
    enabled_flags: [],
    run_async_with_defer: false,
    &block
  )
    T.bind(self, T.untyped)

    app_name = ssr_payload[:name]
    selective_ssr_used = false
    selective_ssr_on = user_or_global_feature_enabled?(:selective_ssr)
    ssr_tier = Alloy::SelectiveSSR.new(
      metadata: Alloy::SSRMetadata.new(
        logged_in: !!logged_in?,
        robot: !!robot?,
        mobile: !!mobile?,
        spammy: !!current_user.try(:spammy?),
        user_agent: T.must(request).user_agent.to_s,
        cpu_bucket: cpu_bucket,
        override: determine_ssr_override(ssr, selective_ssr_on)
      ),
      hints: ssr.is_a?(Alloy::SSRHints) ? ssr : Alloy::SSRHints.new
    )

    if selective_ssr_on
      selective_ssr_used = true
      ssr_enabled = ssr_tier.ssr_enabled?
      report_selective_ssr_stats_with_override(app_name, ssr_tier)
    else
      # ensure we use boolean here
      ssr_enabled = ssr.is_a?(Alloy::SSRHints) ? true : ssr
    end

    ssr_enabled = false if user_or_global_feature_enabled?(:disable_react_ssr)

    GitHub.dogstats.increment(
      "alloy.gh.render.ssr",
      tags: [
        "app_name:#{app_name}",
        "ssr_enabled:#{ssr_enabled}",
        "selective_ssr_used:#{selective_ssr_used}",
        "tier:#{ssr_tier.tier}",
      ]
    )

    report_selective_ssr_stats_without_override(ssr, app_name)

    extracted_fields = {}
    trackers = {}
    if ssr_enabled
      preload_data_timer = Timer.start
      preloaded_data = compute_preloaded_queries(
        variable_overwrite_fns:,
        tags:,
        path_override: path_override,
        precompute_subscription_fns: precompute_subscription_fns,
        add_query_time_tags_fn: add_query_time_tags_fn,
        origin: origin,
        run_defer_directive: run_async_with_defer,
        is_hard_navigation: true
      )

      preload_data_timer.stop
      stats[:preload_data_duration] = preload_data_timer.elapsed_ms
      if !preloaded_data.nil? && preloaded_data[:preloaded_queries].length > 0
        ssr_payload[:data][:payload] ||= {}
        ssr_payload[:data][:payload][:preloadedQueries] = preloaded_data[:preloaded_queries]
        # do only precompute if we have all data if we execute the a query with a defer directive it might not have all the data yet
        ssr_payload[:data][:payload][:preloadedSubscriptions] = preloaded_data[:preloaded_subscriptions] unless run_async_with_defer
      end
    end

    render_timer = Timer.start
    begin
      ssr_response = if ssr_enabled
        ssr_args = {
          **ssr_payload,
          anon: !logged_in?,
          enableCaching: Alloy::AppActor.new(ssr_payload[:name]).feature_enabled?(:alloy_enable_caching),
          clientEnv: client_env(app_specific_flags: enabled_flags),
          tier: ssr_tier.tier,
          colorModes: {
            colorMode: color_mode(current_user).to_s,
            lightTheme: color_mode_light_theme(current_user).to_s,
            darkTheme: color_mode_dark_theme(current_user).to_s
          }
        }
        if preloaded_data.present?
          stats[:query_timings] = []
          preloaded_data[:preloaded_queries].each do |query|
            stats[:query_timings] << query[:timing_data].to_h
            query.delete(:timing_data)
          end
        end

        if run_async_with_defer
          begin
            matching_url_pattern = matching_url_pattern(path_override)
            precompute_subscription_fn = matching_url_pattern ? precompute_subscription_fns[matching_url_pattern[:url]] : nil
            query_callback_fn = matching_url_pattern ? query_callback_fns[matching_url_pattern[:url]] : nil

            defer_and_alloy_timer = Timer.start
            # step 1 kick of the ssr request
            ssr_promise = ssr_component_async(
              ssr_args,
              tags,
              stats
            )

            defer_duration = 0
            # step 2 compute all deferred data
            if preloaded_data.present?
              defer_data_timer = Timer.start
              preloaded_data[:preloaded_queries].each_with_index do |query, index|
                gql_query_object = preloaded_data[:preloaded_query_gql_objects][index].query
                tracker = preloaded_data[:preloaded_query_gql_objects][index].tracker
                # deep dup the data so we don't reset it if an execution error occurs
                result_data = query[:result]["data"].deep_dup
                # execute the deferrals and inject the data into the initial data
                execute_deferral_for_query(gql_query_object, result_data)
                query[:result]["data"] = result_data
                trackers[gql_query_object.context[:query_name]] = tracker unless tracker.nil?

                if !ssr_payload[:data][:payload][:preloadedSubscriptions] && precompute_subscription_fn
                  ssr_payload[:data][:payload][:preloadedSubscriptions] = precompute_subscription_fn.call(query[:queryId], query[:result]) || {}
                end
                query_callback_fn&.call(query[:queryId], query[:result])
              end
              defer_data_timer.stop
              defer_duration = defer_data_timer.elapsed_ms
              stats[:defer_data_duration] = defer_data_timer.elapsed_ms
            end

            stats[:query_deferred_timing_data] = query_deferred_timing_data(trackers)

            # step 3 force for the ssr request to finish
            http_response = ssr_promise.sync

            stats[:alloy_duration] = http_response.headers[GITHUB_ALLOY_DURATION_HEADER]
            http_response.headers.delete(GITHUB_ALLOY_DURATION_HEADER)

            response = Alloy::Response::from_faraday_response(http_response)
            defer_and_alloy_timer.stop
            stats[:alloy_wait_duration] = defer_and_alloy_timer.elapsed_ms - defer_duration
            handle_expected_alloy_errors(response, stats: {}, render_request: ssr_args)

            # step 4 join the ssr response with the deferred data
            response.preloaded_queries = preloaded_data[:preloaded_queries] if preloaded_data.present?
            response
          rescue => e # rubocop:todo Lint/GenericRescue
            GitHub.dogstats.increment("alloy.gh.render.error", tags: ["app_name:#{ssr_args[:name]}", "tier:#{ssr_args[:tier]}", "status:500"])
            GitHub.logger.error(e, "code.namespace": self.class.name, "code.function": __method__, "app_name": ssr_args[:name])
            Alloy::Response.new(status: 500)
          end
        else
          ssr_component(
            ssr_args,
            tags,
            stats
          )
        end
      else
        Alloy::Response.new(status: 403)
      end

      stats[:alloy_response_status] = ssr_response.status

      rails_render_timer = Timer.start
      yield ssr_response
    ensure
      if rails_render_timer.present?
        rails_render_timer.stop # this timer is only for rails render
        GitHub.dogstats.distribution("react.rails.render_html.time", rails_render_timer.elapsed_ms, tags: tags)
        stats[:rails_render_duration] = rails_render_timer.elapsed_ms
      end

      render_timer.stop # this is the timer for alloy render + rails render
      tags << "ssr_attempted:#{!!ssr_enabled}"
      if ssr_enabled
        tags << "ssr_success:#{ssr_response&.success?}"
      end
      GitHub.dogstats.distribution("react.render.html.time", render_timer.elapsed_ms, tags: tags)
      stats[:render_duration] = render_timer.elapsed_ms
    end

  end

  def report_selective_ssr_stats_without_override(ssr, app_name)
    T.bind(self, T.untyped)

    ssr_tier_without_override = Alloy::SelectiveSSR.new(
      metadata: Alloy::SSRMetadata.new(
        logged_in: !!logged_in?,
        robot: !!robot?,
        mobile: !!mobile?,
        spammy: !!current_user.try(:spammy?),
        cpu_bucket: cpu_bucket,
        user_agent: T.must(request).user_agent.to_s,
      ),
      hints: ssr.is_a?(Alloy::SSRHints) ? ssr : Alloy::SSRHints.new
    )

    GitHub.dogstats.increment(
      "alloy.gh.render.tier",
      tags: [
        "app_name:#{app_name}",
        "expected_tier:#{ssr_tier_without_override.tier}",
        "expected_selective_ssr:#{ssr_tier_without_override.ssr_enabled?}",
        "current_ssr_parameter:#{ssr}",
      ])
  end

  def report_selective_ssr_stats_with_override(app_name, ssr_tier)
    GitHub.dogstats.increment(
      "alloy.gh.render.selective_ssr",
      tags: [
        "app_name:#{app_name}",
        "selective_ssr_result:#{ssr_tier.ssr_enabled?}",
        "tier:#{ssr_tier.tier}",
        "logged_in:#{ssr_tier.metadata.logged_in}",
        "robot:#{ssr_tier.metadata.robot}",
        "mobile:#{ssr_tier.metadata.mobile}",
        "spammy:#{ssr_tier.metadata.spammy}",
        "override:#{ssr_tier.metadata.override}",
        "highly_cacheable:#{ssr_tier.hints.highly_cacheable.present?}",
        "no_js_experience:#{ssr_tier.hints.no_js_experience.present?}",
      ]
    )
  end

  def add_preloaded_queries(embedded_data, preloaded_queries)
    if preloaded_queries && preloaded_queries.length > 0
      embedded_data[:payload] ||= {}
      embedded_data[:payload][:preloadedQueries] = preloaded_queries
    end

    embedded_data
  end

  def query_deferred_timing_data(trackers)
    query_deferred_timing_data = []
    trackers.each do |_, tracker|
      next if tracker.nil?
      tracker.deferred_fragment_trackers.each do |deferred_tracker|
        deferred_fragment_timing_data = deferred_tracker.timing_data
        deferred_fragment_timing_data["defer_label"] = deferred_tracker.defer_label
        deferred_fragment_timing_data["type"] = deferred_tracker.execution_type
        deferred_fragment_timing_data["streamed_chunks_count"] = deferred_tracker.streamed_chunks_count
        query_deferred_timing_data << deferred_fragment_timing_data
      end
    end
    query_deferred_timing_data
  end

  def asset_bundle_helper
    @asset_bundle_helper ||= AssetBundlesHelper.new(current_user)
  end

  def sanitized_url
    analytics_location
  rescue => e # rubocop:todo Lint/GenericRescue
    T.must(request).path
  end

  sig { params(payload: T.untyped).returns(T.nilable(T.any(T::Hash[T.untyped, T.untyped], Proc))) }
  def json_payload(payload)
    add_payload_csrf_tokens(payload.is_a?(Proc) ? payload.call : payload)
  end

  sig { params(payload: T.untyped, ssr: T.nilable(T.any(T::Boolean, Alloy::SSRHints))).returns(T.nilable(T.any(T::Hash[T.untyped, T.untyped], Proc))) }
  def html_payload(payload, ssr:)
    # SSR can't handle lazy payloads
    parsed_payload = if payload.is_a?(Proc) && (ssr || !lazy_fetching_enabled?)
      payload.call
    else
      payload
    end

    add_payload_csrf_tokens(parsed_payload)
  end

  sig { params(payload: T.untyped).returns(T.nilable(T.any(T::Hash[T.untyped, T.untyped], Proc))) }
  def add_payload_csrf_tokens(payload)
    return payload if payload.is_a?(Proc)

    payload[:csrf_tokens] = csrf_tokens unless csrf_tokens.nil? || T.must(request).headers["access-control-allow-origin"]
    payload
  end

  sig { returns(T::Boolean) }
  def lazy_fetching_enabled?
    T.bind(self, T.any(ApplicationController, ApplicationComponent))
    !GitHub::AppEnvironment.test? && user_or_global_feature_enabled?(:react_lazy_fetching)
  end

  sig { returns(Alloy::ErrorReporter) }
  def error_reporter
    @@error_reporter ||= Alloy::ErrorReporter.new
  end

  sig { returns(T::Boolean) }
  def json_request?
    T.must(request).headers["Accept"] == "application/json"
  end

  sig { params(block: T.proc.void).returns(T.untyped) }
  def instrument_react_payload_time(&block)
    T.bind(self, T.untyped)
    GitHub.dogstats.distribution_time("react.payload.time", tags: ["controller:#{controller_name}", "action:#{action_name}"]) do
      yield
    end
  end

  sig { params(params: T.untyped).returns(T::Boolean) }
  def flamegraph_mode?(params)
    !!current_user && current_user&.employee? && params && (params[:_tracing_flamegraph] == "true" || params[:flamegraph] == "1")
  end

  def determine_ssr_override(ssr, selective_ssr_enabled)
    if ssr.is_a?(Alloy::SSRHints) || (selective_ssr_enabled && ssr == true)
      # override:nil will enable or disable SSR based on the SelectiveSSR Tier
      return nil
    end
    # override:true will enable SSR regardless of the SelectiveSSR Tier
    # override:false will disable SSR regardless of the SelectiveSSR Tier
    ssr
  end
end
