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
      app_payload_generator: T.untyped, # DEPRECATED: Send this data as layout route data instead. See: https://thehub.github.com/epd/engineering/dev-practicals/frontend/react/data-router/migration/app-payload-deprecation/

      custom_tags: T::Array[String], # Array of strings representing tags that are sent to datadog for metrics. Eg. ["foo:bar"]
      enabled_flags: T.nilable(T::Array[T.untyped]), # DEPRECATED: Send this data as layout route data instead. See: https://thehub.github.com/epd/engineering/dev-practicals/frontend/react/data-router/migration/app-payload-deprecation/

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
    GitHub::TaggingHelper.set_react_tags(env: env)
    request.env[GitHub::TaggingHelper::PROCESS_REQUEST_REACT_TYPE] = "json"

    # Proto payloads resolve to proto3-JSON via the normal dump path; just flag
    # the response so the client decodes `payload[routeId]` with its schema.
    response.headers["X-Proto-JSON"] = "true" if payload.is_a?(ReactPayload::Proto)

    response = {
      meta: {
        title: title
      },
      payload: payload&.as_json || payload,
    }

    response = GitHub::JSON.dump(response)

    render json: response, status: status
  end

  sig do
    params(
      payload: T.nilable(T.any(ReactPayload::Base, T::Hash[Symbol, T.untyped])), # Payload per route used to render the app. It can be either a ReactPayload class or a hash.
      nested_payloads: T::Array[ReactPayload::Base],
      app_name: T.nilable(String), # The react bundle name. If specified, it will be used instead of class-level `react_bundle_name`
      app_payload_generator: T.untyped, # DEPRECATED: Send this data as layout route data instead. See: https://thehub.github.com/epd/engineering/dev-practicals/frontend/react/data-router/migration/app-payload-deprecation/

      custom_tags: T::Array[String], # Array of strings representing tags that are sent to datadog for metrics. Eg. ["foo:bar"]
      enabled_flags: T.nilable(T::Array[T.untyped]), # DEPRECATED: Send this data as layout route data instead. See: https://thehub.github.com/epd/engineering/dev-practicals/frontend/react/data-router/migration/app-payload-deprecation/

      layout: T.any(Symbol, String, FalseClass), # The layout to use.
      layout_locals_generator: T.nilable(T.proc.returns(T::Hash[Symbol, T.untyped])), # function generating a hash of local variables accessible by the layout. Function must return a hash.
      origin: String, # The origin of the request. Defaults to Platform::ORIGIN_API, override only if authorization happens in another place in the request flow
      page_data: T.untyped, # Page metadata.
      stats: T.untyped, # Hash of various stats that can be used for logging purpose.
      status: T.nilable(T.any(Symbol, Integer)), # The HTTP status code to return. Defaults to 200.
      title: T.nilable(String), # Title of the page, not including the "· GitHub" wordmark suffix.
      turbo: T.untyped, # Information about the `turbo-frame` that will wrap the react app.
      url_override: T.nilable(String), # Used to override initial path. Useful for apps being loaded in voltron
      path_override: T.nilable(String), # Used to override initial path. Useful for apps being loaded in voltron
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
    turbo: {},
    url_override: nil,
    path_override: nil
  )
    GitHub::TaggingHelper.set_react_tags(env: env)
    request.env[GitHub::TaggingHelper::PROCESS_REQUEST_APP_NAME] = app_name if app_name

    # Capture proto-backed route ids before `as_json` collapses payloads into
    # hashes; surfaced to the client via `embeddedData.meta.protoRoutes`.
    proto_routes = collect_proto_routes(payload, nested_payloads)

    payload = payload&.as_json || payload

    # Conditionally include the App Shell layout payload behind a feature flag.
    # This allows us to inject a global layout-specific payload alongside the route payloads.
    if should_use_react_app_shell
      render_react_html_full_document(
        payload: payload,
        nested_payloads: nested_payloads,
        app_name: app_name,
        app_payload_generator: app_payload_generator,
        custom_tags: custom_tags,
        enabled_flags: enabled_flags,
        origin: origin,
        page_data: page_data,
        stats: stats,
        status: status,
        title: title,
        turbo: turbo,
        proto_routes: proto_routes,
      )
      return
    end

    nested_payloads.each do |p|
      if p.partial?
        payload[p.route_id.to_sym] = T.cast(p, ReactPayload::Partial).marker
      elsif p.async?
        # Resolved in-flight during SSR and merged into the embedded data afterwards.
        next
      else
        payload[p.route_id.to_sym] = p.resolve
      end
    end

    renderer = React::AppRenderer.new(
      payload: payload,
      custom_tags: custom_tags,
      app_payload_generator: app_payload_generator,
      enabled_flags: enabled_flags,
      layout_locals_generator: layout_locals_generator,
      app_name: app_name,
      origin: origin,
      path_override: path_override,
      controller: T.cast(self, ApplicationController),
      ssr_hints: Alloy::SelectiveSsr::Hints.new,
      request: request,
      disable_ssr: false,
      force_ssr: false,
      skip_preloading_and_ssr: false,
      stats: stats,
      title: title,
      user: current_user,
      data_router_enabled: true,
      url_override: url_override,
      nested_payloads: nested_payloads,
      proto_routes: proto_routes,
    )

    renderer.render do |ssr_response, embedded_data_with_queries, attempted_ssr|
      # Build <link rel="stylesheet"> and <link rel="modulepreload"> tags for
      # dynamic chunks rendered during SSR.  Prevents FOUC and warms JS cache.
      dynamic_chunk_tags = build_dynamic_chunk_links(ssr_response)

      render "react/index", locals: { # rubocop:disable GitHub/RailsControllerRenderLiteral
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
        initial_path: renderer.initial_path,
        lazy: false,
        layout: layout,
        data_router_enabled: true,
        profiling_mode_enabled: feature_enabled_globally_or_for_user?(subject: current_user, feature_name: :react_quality_profiling),
        **renderer.locals,
        **dynamic_chunk_tags,
      }, layout: layout, status: status
    end
  end

  sig do
    params(
      payload: T.nilable(T.any(ReactPayload::Base, T::Hash[Symbol, T.untyped])), # Payload per route used to render the app. It can be either a ReactPayload class or a hash.
      nested_payloads: T::Array[ReactPayload::Base],
      app_name: T.nilable(String), # The react bundle name. If specified, it will be used instead of class-level `react_bundle_name`
      app_payload_generator: T.untyped, # function generating json payload for the app. This is independent of the route and will only be embedded in the html.
      custom_tags: T::Array[String], # Array of strings representing tags that are sent to datadog for metrics. Eg. ["foo:bar"]
      enabled_flags: T.nilable(T::Array[T.untyped]), # Array passing app specific flags to the client side, needed to do more than basic ff checks aka per user or globally
      origin: String, # The origin of the request. Defaults to Platform::ORIGIN_API, override only if authorization happens in another place in the request flow
      page_data: T.untyped, # Page metadata.
      stats: T.untyped, # Hash of various stats that can be used for logging purpose.
      status: T.nilable(T.any(Symbol, Integer)), # The HTTP status code to return. Defaults to 200.
      title: T.nilable(String), # Title of the page, not including the "· GitHub" wordmark suffix.
      turbo: T.untyped, # Information about the `turbo-frame` that will wrap the react app.
      scripts: String, # Script tags as a HTML string
      stylesheets: String, # Stylesheet tags as a HTML string
      proto_routes: T::Array[String], # Route ids whose payloads are proto-encoded, surfaced via embeddedData.meta.protoRoutes.
    ).returns(T.untyped)
  end
  def render_react_html_full_document(
    payload: {},
    nested_payloads: [],
    app_name: nil,
    app_payload_generator: nil,
    custom_tags: [],
    enabled_flags: [],
    origin: Platform::ORIGIN_API,
    page_data: {},
    stats: {},
    status: :ok,
    title: nil,
    turbo: {},
    scripts: "",
    stylesheets: "",
    proto_routes: []
  )
    payload = payload&.as_json || payload
    sso_orgs = global_sso_orgs_payload if logged_in? && show_global_sso_banner?
    nested_payloads << AppShell::AppShellLayoutPayload.new(
      "A message from the App Shell layout",
      current_user: current_user,
      staff_bar_enabled: staff_bar_enabled?,
      canary_cookie_enabled: canary_cookie_enabled?,
      show_ui_opt_out: ui_service_opt_out_enabled?,
      is_ui_opted_out: ui_opted_out?,
      current_repository: current_repository,
      flash: helpers.global_flash,
      sso_orgs: sso_orgs
    )
    nested_payloads.each do |p|
      payload[p.route_id.to_sym] = p.payload
    end

    helpers.stylesheet_required_bundles.each do |bundle|
      self.stylesheet_bundles.add(bundle)
    end
    self.stylesheet_bundles.add(:react)

    app_name = react_app_name(app_name)
    self.javascript_bundles.add(app_name)

    stylesheets = helpers.color_mode_bundles + helpers.controller_stylesheet_bundles

    renderer = React::FullDocumentRenderer.new(
      payload: payload,
      custom_tags: custom_tags,
      enabled_flags: enabled_flags,
      app_name: app_name,
      origin: origin,
      path_override: nil,
      controller: T.cast(self, ApplicationController),
      ssr_hints: Alloy::SelectiveSsr::Hints.new,
      request: request,
      stats: stats,
      title: title,
      user: current_user,
      scripts: helpers.controller_javascript_bundles,
      stylesheets: stylesheets,
      proto_routes: proto_routes
    )

    renderer.render do |ssr_response, _embedded_data, _attempted_ssr|
      # The SSR result already contains a complete <html> document (including embedded data),
      # so we can return it directly with no layout or additional wrapping.
      render html: ssr_response.result&.html_safe, layout: false # rubocop:disable Rails/OutputSafety
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
      skip_preloading_and_ssr: T::Boolean, # Skip both query preloading and SSR when client has cached data
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
    skip_preloading_and_ssr: false,
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
    request.env[GitHub::TaggingHelper::PROCESS_REQUEST_APP_NAME] ||= app_name if app_name
    T.must(custom_tags) << "skip_preloading_and_ssr:#{skip_preloading_and_ssr ? 'true' : 'false'}"

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
          skip_preloading_and_ssr: skip_preloading_and_ssr,
          stats: stats,
          title: title || mainquery_title,
          url_override: url_override,
          user: current_user,
          variable_overwrite_fns: variable_overwrite_fns,
          run_async_with_defer: flamegraph ? false : run_async_with_defer,
          data_router_enabled: data_router_enabled
        )

        renderer.render do |ssr_response, embedded_data_with_queries, attempted_ssr|
          dynamic_chunk_tags = build_dynamic_chunk_links(ssr_response)

          render "react/index", locals: { # rubocop:disable GitHub/RailsControllerRenderLiteral
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
                                          initial_path: renderer.initial_path,
                                          lazy: false,
                                          layout: layout,
                                          data_router_enabled: data_router_enabled,
                                          profiling_mode_enabled: feature_enabled_globally_or_for_user?(subject: current_user, feature_name: :react_quality_profiling),
                                          **renderer.locals,
                                          **dynamic_chunk_tags,
          }, layout: layout, status: status
        end
      end

      format.json do
        request.env[GitHub::TaggingHelper::PROCESS_REQUEST_REACT_TYPE] = "json"

        render json: GitHub::JSON.dump({
          payload: json_payload(payload),
          title: title
        })
      end
    end

    allocated_objects_count = GC.stat(:total_allocated_objects) - start_allocated_objects_count
    stats[:allocated_objects_count] = allocated_objects_count
  end

  sig do
    params(
      payload: T.nilable(T.any(ReactPayload::Base, T::Hash[Symbol, T.untyped])), # Payload per route used to render the app. It can be either a ReactPayload class or a hash.
      status: T.nilable(T.any(Symbol, Integer)), # The HTTP status code to return. Defaults to 200.
    ).returns(T.untyped)
  end
  def render_rails_partial_payload(payload:, status: :ok)
    response.headers["X-HTML-Safe"] = html_safe_nonce

    render json: GitHub::JSON.dump({
      payload: payload&.as_json || payload,
    }), status: status
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

  sig { returns(T::Boolean) }
  def should_use_react_app_shell
    user_or_global_feature_enabled?(:force_react_app_shell)
  end

  # Collects route ids of proto-backed payloads (main + nested) for
  # `embeddedData.meta.protoRoutes`.
  sig do
    params(
      payload: T.nilable(T.any(ReactPayload::Base, T::Hash[Symbol, T.untyped])),
      nested_payloads: T::Array[ReactPayload::Base],
    ).returns(T::Array[String])
  end
  def collect_proto_routes(payload, nested_payloads)
    routes = []
    routes << payload.route_id if payload.is_a?(ReactPayload::Proto)
    nested_payloads.each do |p|
      routes << p.route_id if p.is_a?(ReactPayload::Proto)
    end
    routes
  end

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

  sig { params(partial_or_component: T.any(String, ViewComponent::Base), locals: T::Hash[T.untyped, T.untyped]).returns(String) }
  def render_rails_partial(partial_or_component, locals: {})
    partial = if partial_or_component.is_a?(ViewComponent::Base)
      original_formats = view_context.formats
      begin
        view_context.formats = [:html]
        result = partial_or_component.render_in(view_context)
      ensure
        view_context.formats = original_formats
      end
      result
    else
      render_to_string(partial: partial_or_component, locals: locals, formats: [:html]) # rubocop:disable GitHub/RailsControllerRenderLiteral
    end

    partial.html_safe # rubocop:disable Rails/OutputSafety
  end

  # Inject <link rel="stylesheet"> and <link rel="modulepreload"> tags for
  # dynamic chunks rendered during SSR.  Stylesheets prevent a flash of
  # unstyled content (FOUC); modulepreloads let the browser start fetching
  # JS in parallel, reducing time-to-interactive.
  #
  # Also generates <link rel="preload" as="style"> hints for Voltron fragment
  # rendering where CSS tags appear in <body> rather than <head>.  Browsers
  # that see the preload hint begin fetching the CSS earlier.
  #
  # When the build manifest contains sibling information (chunks imported
  # from the same routes file), low-priority modulepreload hints are emitted
  # for those siblings so the browser warms its cache for likely client-side
  # navigations.
  sig { params(ssr_response: Alloy::Response).returns(T::Hash[Symbol, T.nilable(T::Array[ActiveSupport::SafeBuffer])]) }
  def build_dynamic_chunk_links(ssr_response)
    chunk_names = ssr_response.dynamic_chunks
    return { dynamic_chunk_link_tags: nil, dynamic_chunk_preload_tags: nil } if chunk_names.empty?

    bundles = AssetBundles.new
    crossorigin = GitHub.asset_crossorigin_with_credentials? ? "use-credentials" : "anonymous"

    # --- CSS stylesheet links (critical for FOUC prevention) ---
    css_files = bundles.dynamic_css_files(chunk_names)
    css_tags = css_files.map do |file|
      href = bundles.bundle_url(file, expand: false)
      ActionController::Base.helpers.tag(:link, rel: "stylesheet", href: href, media: "all", crossorigin: crossorigin)
    end

    # --- CSS preload hints (for Voltron fragments rendered without a layout) ---
    # When the fragment is stitched into the page body, preload hints help the
    # browser discover these stylesheets before it encounters the <link rel="stylesheet">.
    css_preload_tags = css_files.map do |file|
      href = bundles.bundle_url(file, expand: false)
      ActionController::Base.helpers.tag(:link, rel: "preload", href: href, as: "style", crossorigin: crossorigin)
    end

    # --- JS modulepreload links for rendered chunks (high priority) ---
    js_files = bundles.dynamic_js_files(chunk_names)
    js_tags = js_files.map do |file|
      href = bundles.bundle_url(file, expand: false)
      ActionController::Base.helpers.tag(:link, rel: "modulepreload", href: href, crossorigin: crossorigin)
    end

    # --- Prefetch sibling chunks (low priority) ---
    # Siblings are dynamic() components from the same routes file that
    # didn't render on this page.  Preloading their JS and CSS warms the
    # browser cache for client-side navigations.
    prefetch_chunk_names = bundles.dynamic_sibling_chunk_names(chunk_names)

    prefetch_css_files = bundles.dynamic_css_files(prefetch_chunk_names)
    prefetch_css_tags = prefetch_css_files.map do |file|
      href = bundles.bundle_url(file, expand: false)
      ActionController::Base.helpers.tag(:link, rel: "prefetch", href: href, as: "style", crossorigin: crossorigin)
    end

    prefetch_js_files = bundles.dynamic_js_files(prefetch_chunk_names)
    prefetch_js_tags = prefetch_js_files.map do |file|
      href = bundles.bundle_url(file, expand: false)
      ActionController::Base.helpers.tag(:link, rel: "modulepreload", href: href, crossorigin: crossorigin, fetchpriority: "low")
    end

    all_tags = css_tags + js_tags + prefetch_css_tags + prefetch_js_tags
    return { dynamic_chunk_link_tags: nil, dynamic_chunk_preload_tags: nil } if all_tags.empty?

    {
      dynamic_chunk_link_tags: all_tags,
      dynamic_chunk_preload_tags: css_preload_tags,
    }
  end
end
