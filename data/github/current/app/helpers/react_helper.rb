# typed: true
# frozen_string_literal: true

require "alloy/renderer"
require "alloy/selective_ssr"
require "alloy/error_reporter"
require "alloy/app_actor"
require "scientist"

module ReactHelper
  extend T::Helpers
  extend T::Sig

  extend ActiveSupport::Concern
  include ColorHelper
  include PersistedGraphqlQueryHelper
  include Platform::Helpers::DeferredQueryHelper
  include UrlSanitizingHelper
  include Scientist
  include ClientEnvHelper

  GITHUB_ALLOY_DURATION_HEADER = "X-GitHub-Alloy-Duration".freeze

  abstract!

  sig { abstract.returns(T.nilable(::User)) }
  def current_user; end

  module ClassMethods
    extend T::Sig

    sig { returns(T.nilable(String)) }
    attr_accessor :react_bundle_name
  end
  mixes_in_class_methods(ClassMethods)

  # Renders a react application in the GitHub monolith.
  #
  # payload: Payload per route used to render the app. It can be either a JSON object or a Proc.
  # app_payload_generator: function generating json payload for the app. This is independent of the route and will only be embedded in the html.
  # title: Title of the page, not including the "· GitHub" wordmark suffix.
  # page_data: Page metadata.
  # layout: The layout to use.
  # turbo: Information about the `turbo-frame` that will wrap the react app.
  # ssr: Boolean defaulting to true signaling if the app should be rendered server side.
  # status: The HTTP status code to return. Defaults to 200.
  # layout_locals_generator: function generating a hash of local variables accessible by the layout. Function must return a hash.
  # flamegraph_mode: flamegraph mode - render html even if json is requested. default false
  # app_name: The react bundle name. If specified, it will be used instead of class-level `react_bundle_name`
  # origin: The origin of the request. Defaults to Platform::ORIGIN_API, override only if authorization happens in another place in the request flow
  # run_async_with_defer: Boolean defaulting to false signaling if the app should be rendered with the defer directive.
  def render_react_app(
    payload: {},
    app_payload_generator: nil,
    title: nil,
    page_data: {},
    layout: :default,
    timers: {},
    turbo: {},
    ssr: false,
    status: :ok,
    url_override: nil,
    path_override: nil,
    variable_overwrite_fns: {},
    precompute_subscription_fns: {},
    custom_tags: [],
    layout_locals_generator: nil,
    flamegraph_mode: false,
    app_name: nil,
    origin: Platform::ORIGIN_API,
    run_async_with_defer: false
  )
    T.bind(self, T.untyped)
    respond_to do |format|

      # Note that `format.html` comes *before* `format.json`.
      # This is important. It means it will use HTML, by default, if the Accept header doesn't spell out
      # an obvious preference. E.g. `Accept: */*` will yield HTML. But `Accept: application/json`
      # will yield JSON. A Chrome browsers, as of 2024, sends something
      # like `Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,<BREAK>
      # image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7`.

      format.html do
        render_html(
          payload,
          app_payload_generator,
          title,
          page_data,
          layout,
          timers,
          turbo,
          ssr,
          status,
          url_override,
          path_override,
          variable_overwrite_fns,
          precompute_subscription_fns,
          custom_tags,
          layout_locals_generator,
          app_name,
          origin,
          run_async_with_defer
        )
      end

      format.json do
        if flamegraph_mode
          render_html(
            payload,
            app_payload_generator,
            title,
            page_data,
            layout,
            timers,
            turbo,
            ssr,
            status,
            url_override,
            path_override,
            variable_overwrite_fns,
            precompute_subscription_fns,
            custom_tags,
            layout_locals_generator,
            app_name,
            origin,
            false,
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
  end

  # Renders a react partial in the GitHub monolith.
  #
  # name: Name of the partial. Should match the directory name within react-partials
  # props: props to pass to the partial component
  # ssr: Boolean defaulting to true signaling if the app should be rendered server side.
  # class_name: Additional css class/classes to add to the react-partial element
  # origin: the request origin to use in the platform flow
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
        ssr: ssr_response.success?,
        ssr_error_script_tag: html_safe_json_script_tag(ssr_response.error, "react-partial.ssrError"),
        data_script_tag: html_safe_json_script_tag(serialize(embedded_data), "react-partial.embeddedData"),
        react_root_tag: html_safe_react_root_tag(ssr_response.result, "react-partial.reactRoot"),
        class_name: class_name,
      }
    end
  end

  def serialize(data)
    GitHub::JSON.dump(data)
  end

  def html_safe_json_script_tag(data, target)
    return unless data
    content_tag(
      :script,
      json_escape(data).html_safe, # rubocop:disable Rails/OutputSafety
      type: "application/json",
      data: { target: target }
    )
  end

  def html_safe_react_root_tag(ssr_result, target)
    content_tag(
      :div,
      ssr_result&.html_safe,  # rubocop:disable Rails/OutputSafety
      data: { target: target }
    )
  end

  def add_client_feature_flag(*flag_names, entity: current_user, &check)
    @client_feature_flags ||= {}
    flag_names.each do |flag_name|
      next unless flag_name.present? && flag_name.is_a?(String) || flag_name.is_a?(Symbol)
      if flag_name.is_a?(String)
        flag_name = flag_name.to_sym
      end
      if block_given?
        result = check.call(flag_name, entity)
        @client_feature_flags[flag_name] = result
      else
        T.bind(self, ApplicationController)
        result = feature_enabled_globally_or_for_current_user_or_entity?(flag_name, entity)
        @client_feature_flags[flag_name] = result
      end
    end
    @client_feature_flags
  end

  def add_csrf_token(path, method)
    # Raise unknown format to respond with a 406 in development because csrf is not allowed with access-control-allow-origin
    raise ActionController::UnknownFormat if T.must(request).headers["access-control-allow-origin"] && Rails.env.development?
    T.bind(self, ApplicationController)
    @csrf_tokens ||= {}
    @csrf_tokens[path] ||= {}
    @csrf_tokens[path][method] ||= authenticity_token_for(path, method: method)
  end

  def ssr_component_async(render_request, custom_tags, timers)
    T.bind(self, T.untyped)
    ::Alloy::AsyncRenderer.render(
      request: render_request,
      metadata: build_metadata,
    )
  end

  def handle_expected_alloy_errors(response, timers: {}, render_request: {})
    if response.error.present?
      timers[:alloy_render_error] = true
      GitHub.dogstats.increment("alloy.gh.render.error", tags: ["app_name:#{render_request[:name]}", "status:#{response.status}"])
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

  def ssr_component(render_request, custom_tags, timers)
    status_tag = "status:unknown"
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
      timers[:alloy_render_duration] = timing

      set_ssr_request_tags(timing)
      handle_expected_alloy_errors(response, timers: timers, render_request: render_request)

      status_tag = "status:#{response.status}"
      response
    rescue => e # rubocop:todo Lint/GenericRescue
      status_tag = "status:500"
      GitHub.dogstats.increment("alloy.gh.render.error", tags: ["app_name:#{render_request[:name]}", status_tag])
      GitHub.logger.error(e, "code.namespace": self.class.name, "code.function": __method__, "app_name": render_request[:name])
      Alloy::Response.new(status: 500)
    ensure
      GitHub.dogstats.distribution("alloy.gh.total.rails.time", T.must(request).env[GitHub::TaggingHelper::ALLOY_WAIT_TIME], tags: [status_tag] + custom_tags)
    end
  end

  def color_mode(user)
    cookie_color_mode = T.must(request).cookies["preferred_color_mode"] || ColorMode.default
    color_mode_with_override = color_mode_with_override(user)
    return cookie_color_mode if color_mode_with_override.auto?
    color_mode_with_override
  end

  def build_metadata
    T.bind(self, T.untyped)
    metadata = {
      controller: controller_name,
      action: action_name,
      logged_in: logged_in?,
    }

    referrer_controller_action = GitHub::TaggingHelper.calculate_referrer(T.must(request).env)
    referrer_controller_action.each do |tag|
      (tag_name, tag_value) = tag.split(":")
      metadata[tag_name] = tag_value
    end
    metadata
  end

  private

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

  def render_html(
    payload,
    app_payload_generator,
    title,
    page_data,
    layout,
    timers,
    turbo,
    ssr,
    status,
    url_override,
    path_override,
    variable_overwrite_fns,
    precompute_subscription_fns,
    custom_tags,
    layout_locals_generator,
    app_name,
    origin,
    run_async_with_defer = false
  )
    lazy = lazy_fetching_enabled? && payload.is_a?(Proc) && !ssr
    render_payload = html_payload(payload, ssr: ssr)

    T.must(request).env[GitHub::TaggingHelper::PROCESS_REQUEST_REACT_TYPE] = "html"
    app_payload = app_payload_generator.call if app_payload_generator
    T.bind(self, T.untyped)
    app_name = app_name || self.class.react_bundle_name || controller_name.dasherize

    unless @client_feature_flags.nil?
      app_payload ||= {}
      app_payload[:enabled_features] = @client_feature_flags.merge(app_payload[:enabled_features] || {})
    end

    locals = layout_locals_generator&.call || {}
    raise ArgumentError.new("layout_locals_generator must return a hash") unless locals.is_a?(Hash)

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
      timers: timers,
      variable_overwrite_fns: variable_overwrite_fns,
      precompute_subscription_fns: precompute_subscription_fns,
      path_override: path_override,
      origin: origin,
      run_async_with_defer: run_async_with_defer,
    ) do |ssr_response|
      embedded_data_with_queries = add_preloaded_queries(embedded_data, ssr_response.preloaded_queries)
      render "react/index", locals: { # rubocop:disable GitHub/RailsViewRenderPathsExist
                                      ssr: ssr_response.success?,
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

  def render_with_ssr(
    ssr:,
    ssr_payload:,
    tags: [],
    timers: {},
    variable_overwrite_fns: {},
    precompute_subscription_fns: {},
    path_override: nil,
    origin: nil,
    run_async_with_defer: false
  )
    T.bind(self, T.untyped)
    ssr_enabled = ssr && !user_or_global_feature_enabled?(:disable_react_ssr)

    extracted_fields = {}
    trackers = {}
    if ssr_enabled
      preload_data_timer = Timer.start
      preloaded_data = compute_preloaded_queries(
        variable_overwrite_fns:,
        tags:,
        path_override: path_override,
        precompute_subscription_fns: precompute_subscription_fns,
        origin: origin,
        run_defer_directive: run_async_with_defer,
        is_hard_navigation: true
      )

      preload_data_timer.stop
      timers[:preload_data_duration] = preload_data_timer.elapsed_ms
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
          anon: !logged_in? && user_or_global_feature_enabled?(:alloy_anon_requests),
          enableCaching: Alloy::AppActor.new(ssr_payload[:name]).feature_enabled?(:alloy_enable_caching),
          clientEnv: client_env,
          colorModes: {
            colorMode: color_mode(current_user).to_s,
            lightTheme: color_mode_light_theme(current_user).to_s,
            darkTheme: color_mode_dark_theme(current_user).to_s
          }
        }
        if preloaded_data.present?
          timers[:query_timings] = []
          preloaded_data[:preloaded_queries].each do |query|
            timers[:query_timings] << query[:timing_data].to_h
            query.delete(:timing_data)
          end
        end

        if run_async_with_defer
          begin
            matching_url_pattern = matching_url_pattern(path_override)
            precompute_subscription_fn = matching_url_pattern ? precompute_subscription_fns[matching_url_pattern[:url]] : nil

            defer_and_alloy_timer = Timer.start
            # step 1 kick of the ssr request
            ssr_promise = ssr_component_async(
              ssr_args,
              tags,
              timers
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
              end
              defer_data_timer.stop
              defer_duration = defer_data_timer.elapsed_ms
              timers[:defer_data_duration] = defer_data_timer.elapsed_ms
            end

            timers[:query_deferred_timing_data] = query_deferred_timing_data(trackers)

            # step 3 force for the ssr request to finish
            http_response = ssr_promise.sync

            timers[:alloy_duration] = http_response.headers[GITHUB_ALLOY_DURATION_HEADER]
            http_response.headers.delete(GITHUB_ALLOY_DURATION_HEADER)

            response = Alloy::Response::from_faraday_response(http_response)
            defer_and_alloy_timer.stop
            timers[:alloy_wait_duration] = defer_and_alloy_timer.elapsed_ms - defer_duration
            handle_expected_alloy_errors(response, timers: {}, render_request: ssr_args)

            # step 4 join the ssr response with the deferred data
            response.preloaded_queries = preloaded_data[:preloaded_queries] if preloaded_data.present?
            response
          rescue => e # rubocop:todo Lint/GenericRescue
            GitHub.dogstats.increment("alloy.gh.render.error", tags: ["app_name:#{ssr_args[:name]}", "status:500"])
            GitHub.logger.error(e, "code.namespace": self.class.name, "code.function": __method__, "app_name": ssr_args[:name])
            Alloy::Response.new(status: 500)
          end
        else
          ssr_component(
            ssr_args,
            tags,
            timers
          )
        end
      else
        Alloy::Response.new(status: 403)
      end

      timers[:alloy_response_status] = ssr_response.status

      rails_render_timer = Timer.start
      yield ssr_response
    ensure
      if rails_render_timer.present?
        rails_render_timer.stop # this timer is only for rails render
        GitHub.dogstats.distribution("react.rails.render_html.time", rails_render_timer.elapsed_ms, tags: tags)
        timers[:rails_render_duration] = rails_render_timer.elapsed_ms
      end

      render_timer.stop # this is the timer for alloy render + rails render
      tags << "ssr_attempted:#{!!ssr_enabled}"
      if ssr_enabled
        tags << "ssr_success:#{ssr_response&.success?}"
      end
      GitHub.dogstats.distribution("react.render.html.time", render_timer.elapsed_ms, tags: tags)
      timers[:render_duration] = render_timer.elapsed_ms
    end

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

  def json_payload(payload)
    add_payload_csrf_tokens(payload.is_a?(Proc) ? payload.call : payload)
  end

  def html_payload(payload, ssr:)
    # SSR can't handle lazy payloads
    parsed_payload = if payload.is_a?(Proc) && (ssr || !lazy_fetching_enabled?)
      payload.call
    else
      payload
    end

    add_payload_csrf_tokens(parsed_payload)
  end

  def add_payload_csrf_tokens(payload)
    return payload if payload.is_a?(Proc)

    payload[:csrf_tokens] = @csrf_tokens unless @csrf_tokens.nil? || T.must(request).headers["access-control-allow-origin"]
    payload
  end

  def lazy_fetching_enabled?
    T.bind(self, T.any(ApplicationController, ApplicationComponent))
    !GitHub::AppEnvironment.test? && user_or_global_feature_enabled?(:react_lazy_fetching)
  end

  def error_reporter
    @@error_reporter ||= Alloy::ErrorReporter.new
  end

  def json_request?
    T.must(request).headers["Accept"] == "application/json"
  end

  def instrument_react_payload_time
    T.bind(self, T.untyped)
    GitHub.dogstats.distribution_time("react.payload.time", tags: ["controller:#{controller_name}", "action:#{action_name}"]) do
      yield
    end
  end
end
