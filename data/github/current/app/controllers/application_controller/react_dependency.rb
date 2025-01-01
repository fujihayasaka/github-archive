# typed: true
# frozen_string_literal: true

require "react_payload"

module ApplicationController::ReactDependency
  extend T::Helpers
  extend ActiveSupport::Concern

  requires_ancestor { ApplicationController }

  include React::TagDependency

  class_methods do
    sig { returns(T.nilable(String)) }
    def react_bundle_name
      @react_bundle_name
    end

    sig { params(value: T.nilable(String)).void }
    def react_bundle_name=(value)
      @react_bundle_name = T.let(value, T.nilable(String))
    end
  end

  sig do
    params(
      payload: T.nilable(T.any(ReactPayload::Base, T::Hash[Symbol, T.untyped])), # Payload per route used to render the app. It can be either a ReactPayload class or a hash.
      nested_payloads: T.nilable(Proc), # A proc that returns an array of ReactPayloads to be included in the payload that can be skipped for JSON responses
      app_name: T.nilable(String), # The react bundle name. If specified, it will be used instead of class-level `react_bundle_name`
      app_payload_generator: T.untyped, # function generating json payload for the app. This is independent of the route and will only be embedded in the html.
      custom_tags: T::Array[String], # Array of strings representing tags that are sent to datadog for metrics. Eg. ["foo:bar"]
      enabled_flags: T.nilable(T::Array[T.untyped]), # Array passing app specific flags to the client side, needed to do more than basic ff checks aka per user or globally
      layout: T.any(Symbol, String, FalseClass), # The layout to use.
      layout_locals_generator: T.nilable(T.proc.returns(T::Hash[Symbol, T.untyped])), # function generating a hash of local variables accessible by the layout. Function must return a hash.
      origin: String, # The origin of the request. Defaults to Platform::ORIGIN_API, override only if authorization happens in another place in the request flow
      page_data: T.untyped, # Page metadata.
      stats: T.untyped, # Hash of various stats that can be used for logging purpose.
      status: T.nilable(T.any(Symbol, Integer)), # The HTTP status code to return. Defaults to 200.
      title: T.nilable(String), # Title of the page, not including the "· GitHub" wordmark suffix. Defaults as nil.
      turbo: T.untyped, # Information about the `turbo-frame` that will wrap the react app.
    ).returns(T.untyped)
  end
  def respond_with_react(
    payload: {},
    nested_payloads: nil,
    app_name: nil,
    app_payload_generator: nil,
    custom_tags: [],
    enabled_flags: [],
    layout: :default,
    layout_locals_generator: nil,
    origin: Platform::ORIGIN_API,
    page_data: {},
    stats: {},
    status: :ok,
    title: nil,
    turbo: {}
  )
    respond_to do |format|
      format.html do
        render_react_html(
          payload: payload,
          nested_payloads: nested_payloads ? nested_payloads.call : [],
          app_name: app_name,
          app_payload_generator: app_payload_generator,
          custom_tags: custom_tags,
          enabled_flags: enabled_flags,
          layout: layout,
          layout_locals_generator: layout_locals_generator,
          origin: origin,
          page_data: page_data,
          stats: stats,
          status: status,
          title: title,
          turbo: turbo,
        )
      end

      format.json do
        render_react_json(payload: payload, title: title, status: status)
      end
    end
  end

  sig do
    params(
      payload: T.nilable(T.any(ReactPayload::Base, T::Hash[Symbol, T.untyped])), # Payload per route used to render the app. It can be either a ReactPayload class or a hash.
      status: T.nilable(T.any(Symbol, Integer)), # The HTTP status code to return. Defaults to 200.
      title: T.nilable(String), # Title of the page, not including the "· GitHub" wordmark suffix. Defaults as nil.
    ).returns(T.untyped)
  end
  def render_react_json(payload:, status: :ok, title: nil)
    response = {
      meta: {
        title: title
      },
      payload: payload&.as_json || payload,
    }

    response = GitHub::JSON.dump(response) if feature_enabled_globally_or_for_user?(feature_name: :react_data_router_json_serialization, subject: current_user)

    render json: response, status: status
  end

  sig do
    params(
      payload: T.nilable(T.any(ReactPayload::Base, T::Hash[Symbol, T.untyped])), # Payload per route used to render the app. It can be either a ReactPayload class or a hash.
      nested_payloads: T::Array[ReactPayload::Base],
      app_name: T.nilable(String), # The react bundle name. If specified, it will be used instead of class-level `react_bundle_name`
      app_payload_generator: T.untyped, # function generating json payload for the app. This is independent of the route and will only be embedded in the html.
      custom_tags: T::Array[String], # Array of strings representing tags that are sent to datadog for metrics. Eg. ["foo:bar"]
      enabled_flags: T.nilable(T::Array[T.untyped]), # Array passing app specific flags to the client side, needed to do more than basic ff checks aka per user or globally
      layout: T.any(Symbol, String, FalseClass), # The layout to use.
      layout_locals_generator: T.nilable(T.proc.returns(T::Hash[Symbol, T.untyped])), # function generating a hash of local variables accessible by the layout. Function must return a hash.
      origin: String, # The origin of the request. Defaults to Platform::ORIGIN_API, override only if authorization happens in another place in the request flow
      page_data: T.untyped, # Page metadata.
      stats: T.untyped, # Hash of various stats that can be used for logging purpose.
      status: T.nilable(T.any(Symbol, Integer)), # The HTTP status code to return. Defaults to 200.
      title: T.nilable(String), # Title of the page, not including the "· GitHub" wordmark suffix.
      turbo: T.untyped, # Information about the `turbo-frame` that will wrap the react app.
    ).returns(T.untyped)
  end
  def render_react_html(
    payload: {},
    nested_payloads: [],
    app_name: nil,
    app_payload_generator: nil,
    custom_tags: [],
    enabled_flags: [],
    layout: :default,
    layout_locals_generator: nil,
    origin: Platform::ORIGIN_API,
    page_data: {},
    stats: {},
    status: :ok,
    title: nil,
    turbo: {}
  )
    payload = payload&.as_json || payload
    nested_payloads.each do |p|
      payload[p.route_id.to_sym] = p.payload
    end

    renderer = React::AppRenderer.new(
      payload: payload,
      custom_tags: custom_tags,
      app_payload_generator: app_payload_generator,
      enabled_flags: enabled_flags,
      layout_locals_generator: layout_locals_generator,
      app_name: app_name,
      origin: origin,
      path_override: nil,
      controller: T.cast(self, ApplicationController),
      ssr_hints: Alloy::SelectiveSsr::Hints.new,
      request: request,
      disable_ssr: false,
      force_ssr: false,
      stats: stats,
      title: title,
      user: current_user,
      data_router_enabled: true,
    )

    renderer.render do |ssr_response, embedded_data_with_queries, attempted_ssr|
      render "react/index", locals: { # rubocop:disable GitHub/RailsViewRenderPathsExist, GitHub/RailsControllerRenderLiteral
        page_data: page_data,
        ssr: ssr_response.success?,
        attempted_ssr: attempted_ssr,
        ssr_error_script_tag: html_safe_json_script_tag(ssr_response.error, "react-app.ssrError"),
        data_script_tag: html_safe_json_script_tag(GitHub::JSON.dump(embedded_data_with_queries), "react-app.embeddedData"),
        react_root_tag: html_safe_react_root_tag(ssr_response.result, "react-app.reactRoot"),
        payload: payload,
        title: title,
        javascript_bundle_name: renderer.app_name,
        turbo: turbo,
        initial_path: request.fullpath,
        lazy: false,
        layout: layout,
        data_router_enabled: true,
        **renderer.locals,
      }, layout: layout, status: status
    end
  end

  sig do
    params(
      payload: T.untyped, # Payload per route used to render the app. It can be either a JSON object or a Proc.
      app_payload_generator: T.untyped, # function generating json payload for the app. This is independent of the route and will only be embedded in the html.
      title: T.nilable(String), # Title of the page, not including the "· GitHub" wordmark suffix.
      page_data: T.untyped, # Page metadata.
      layout: T.any(Symbol, String, FalseClass), # The layout to use.
      stats: T.untyped, # Hash of various stats that can be used for logging purpose.
      turbo: T.nilable(T::Hash[Symbol, String]), # Information about the `turbo-frame` that will wrap the react app.
      ssr_hints: Alloy::SelectiveSsr::Hints,
      disable_ssr: T::Boolean, # Override Selective SSR and disable SSR
      force_ssr: T::Boolean, # Override Selective SSR and enable SSR
      status: T.nilable(T.any(Symbol, Integer)), # The HTTP status code to return. Defaults to 200.
      url_override: T.nilable(String),
      path_override: T.nilable(String),
      variable_overwrite_fns: T.untyped,
      precompute_subscription_fns: T.untyped,
      query_callback_fns: T::Hash[String, T.proc.params(arg0: T.untyped, arg1: T.untyped).returns(T.untyped)], # A map of routes to callback functions to execute after certain queries complete
      custom_tags: T.nilable(T::Array[String]),
      layout_locals_generator: T.nilable(T.proc.returns(T::Hash[Symbol, T.untyped])), # function generating a hash of local variables accessible by the layout. Function must return a hash.
      app_name: T.nilable(String), # The react bundle name. If specified, it will be used instead of class-level `react_bundle_name`
      origin: String, # The origin of the request. Defaults to Platform::ORIGIN_API, override only if authorization happens in another place in the request flow
      run_async_with_defer: T::Boolean, # Boolean defaulting to false signaling if the app should be rendered with the defer directive.
      enabled_flags: T.nilable(T::Array[T.untyped]), # Array passing app specific flags to the client side, needed to do more than basic ff checks aka per user or globally
      add_query_time_tags_fn: T.nilable(T.proc.params(arg0: String, arg1: T::Hash[T.untyped, T.untyped]).returns(T.nilable(T::Array[String]))),
      data_router_enabled: T.nilable(T::Boolean)
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
    ssr_hints: Alloy::SelectiveSsr::Hints.new,
    disable_ssr: false,
    force_ssr: false,
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
    add_query_time_tags_fn: nil,
    data_router_enabled: false
  )
    start_allocated_objects_count = GC.stat(:total_allocated_objects)
    GitHub::TaggingHelper.set_react_tags(env: env)

    mainquery_title = T.let(nil, T.untyped)
    if data_router_enabled && !title
      # When you use Data Router, you put the title next to `mainQuery` in the main
      # payload (by route ID).
      # But for SSR rendering, we need the title out of that payload.
      payload.each_value do |value|
        if value.key?(:mainQuery) && value[:title]
          mainquery_title = value[:title]
        end
      end
    end

    # if this is a flamegraph request, make sure we include the alloy part
    flamegraph = flamegraph_mode?(params)
    request.format = :html if flamegraph

    respond_to do |format|
      # Note that `format.html` comes *before* `format.json`.
      # This is important. It means it will use HTML, by default, if the Accept header doesn't spell out
      # an obvious preference. E.g. `Accept: */*` will yield HTML. But `Accept: application/json`
      # will yield JSON. A Chrome browsers, as of 2024, sends something
      # like `Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,<BREAK>
      # image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7`.
      format.html do
        self.stylesheet_bundles.add(:react) if user_or_global_feature_enabled?(:react_app_dvh)

        renderer = React::AppRenderer.new(
          add_query_time_tags_fn: add_query_time_tags_fn,
          app_name: app_name,
          app_payload_generator: app_payload_generator,
          controller: T.cast(self, ApplicationController),
          custom_tags: custom_tags || [],
          enabled_flags: enabled_flags,
          layout_locals_generator: layout_locals_generator,
          origin: origin,
          path_override: path_override,
          payload: payload,
          precompute_subscription_fns: precompute_subscription_fns,
          query_callback_fns: query_callback_fns,
          request: request,
          ssr_hints: ssr_hints,
          disable_ssr: disable_ssr,
          force_ssr: force_ssr,
          stats: stats,
          title: title || mainquery_title,
          url_override: url_override,
          user: current_user,
          variable_overwrite_fns: variable_overwrite_fns,
          run_async_with_defer: flamegraph ? false : run_async_with_defer,
          data_router_enabled: data_router_enabled
        )

        renderer.render do |ssr_response, embedded_data_with_queries, attempted_ssr|
          render "react/index", locals: { # rubocop:disable GitHub/RailsViewRenderPathsExist, GitHub/RailsControllerRenderLiteral
                                          ssr: ssr_response.success?,
                                          attempted_ssr: attempted_ssr,
                                          ssr_error_script_tag: html_safe_json_script_tag(ssr_response.error, "react-app.ssrError"),
                                          data_script_tag: html_safe_json_script_tag(GitHub::JSON.dump(embedded_data_with_queries), "react-app.embeddedData"),
                                          react_root_tag: html_safe_react_root_tag(ssr_response.result, "react-app.reactRoot"),
                                          payload: payload,
                                          title: title || mainquery_title,
                                          page_data: page_data,
                                          javascript_bundle_name: renderer.app_name,
                                          turbo: turbo,
                                          initial_path: path_override || request.fullpath,
                                          lazy: false,
                                          layout: layout,
                                          data_router_enabled: data_router_enabled,
                                          **renderer.locals,
          }, layout: layout, status: status
        end
      end

      format.json do
        request.env[GitHub::TaggingHelper::PROCESS_REQUEST_REACT_TYPE] = "json"

        render json: GitHub::JSON.dump({  # rubocop:disable GitHub/RailsViewRenderLiteral
          payload: json_payload(payload),
          title: title
        })
      end
    end

    allocated_objects_count = GC.stat(:total_allocated_objects) - start_allocated_objects_count
    stats[:allocated_objects_count] = allocated_objects_count
  end

  APP_TYPE_HEADER = "X-GitHub-App-Type"

  def get_app_type_header
    client_version = request.headers[APP_TYPE_HEADER]
  end

  def check_app_type_header
    return true if get_app_type_header == "dataRouter"
    return false if get_app_type_header == "navigator"

    nil
  end

  private

  sig { params(payload: T.untyped).returns(T.nilable(T.any(T::Hash[T.untyped, T.untyped], Proc))) }
  def json_payload(payload)
    add_payload_csrf_tokens(payload.is_a?(Proc) ? payload.call : payload)
  end

  sig { params(payload: T.untyped).returns(T.nilable(T.any(T::Hash[T.untyped, T.untyped], Proc))) }
  def add_payload_csrf_tokens(payload)
    return payload if payload.is_a?(Proc)

    payload[:csrf_tokens] = csrf_tokens unless csrf_tokens.nil? || request.headers["access-control-allow-origin"]
    payload
  end

  sig { params(params: T.untyped).returns(T::Boolean) }
  def flamegraph_mode?(params)
    !!current_user && current_user&.employee? && params && (params[:_tracing_flamegraph] == "true" || params[:flamegraph] == "1")
  end

  sig { params(app_name_override: T.nilable(String)).returns(String) }
  def react_app_name(app_name_override)
    app_name_override || T.cast(self.class, T.class_of(ApplicationController)).react_bundle_name || controller_name.dasherize
  end

  sig { returns(T::Boolean) }
  def navigating_between_repos?
    _, from_owner, from_repo = URI.parse(request.referrer).path&.split("/")

    # not coming from a repo
    return false if !from_owner || !from_repo

    _, to_owner, to_repo = request.path&.split("/")

    # not going to a repo
    return false if !to_owner || !to_repo

    to_owner != from_owner || to_repo != from_repo
  rescue URI::Error, Addressable::URI::InvalidURIError
    true # If something is wrong with the referrer, don't soft-navigate to be safe
  end

  sig { params(block: T.proc.void).returns(T.untyped) }
  def instrument_react_payload_time(&block)
    GitHub.dogstats.distribution_time("react.payload.time", tags: ["controller:#{controller_name}", "action:#{action_name}"]) do
      yield
    end
  end

  sig { returns(T::Boolean) }
  def json_request?
    request.headers["Accept"] == "application/json"
  end
end
