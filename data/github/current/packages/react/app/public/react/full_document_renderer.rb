# typed: strict
# frozen_string_literal: true

module React
  class FullDocumentRenderer
    sig { returns(String) }
    attr_reader :app_name

    sig { returns(String) }
    attr_reader :initial_path

    sig do
      params(
        app_name: T.nilable(String),
        controller: ApplicationController,
        custom_tags: T::Array[String],
        enabled_flags: T.nilable(T::Array[T.untyped]),
        origin: T.untyped,
        path_override: T.nilable(String),
        payload: T.nilable(T.any(T.proc.returns(T::Hash[Symbol, T.untyped]), T::Hash[Symbol, T.untyped])),
        request: ActionDispatch::Request,
        ssr_hints: Alloy::SelectiveSsr::Hints,
        scripts: String,
        stats: T::Hash[Symbol, T.untyped],
        stylesheets: String,
        title: T.nilable(String),
        user: T.nilable(User),
        add_query_time_tags_fn: T.nilable(T.proc.params(arg0: String, arg1: T::Hash[T.untyped, T.untyped]).returns(T.nilable(T::Array[String]))),
        precompute_subscription_fns: T::Hash[String, T.proc.params(arg0: T.untyped, arg1: T.untyped).returns(T.untyped)],
        query_callback_fns: T::Hash[String, T.proc.params(arg0: T.untyped, arg1: T.untyped).returns(T.untyped)],
        url_override: T.nilable(String),
        variable_overwrite_fns: T::Hash[Symbol, T.proc.params(path_variables: T::Hash[T.untyped, T.untyped]).returns(T.untyped)],
        run_async_with_defer: T::Boolean,
        proto_routes: T::Array[String],
      ).void
    end
    def initialize(
      app_name:,
      controller:,
      custom_tags:,
      enabled_flags:,
      origin:,
      path_override:,
      payload:,
      request:,
      ssr_hints:,
      scripts:,
      stats:,
      stylesheets:,
      title:,
      user:,
      add_query_time_tags_fn: nil,
      precompute_subscription_fns: {},
      query_callback_fns: {},
      url_override: nil,
      variable_overwrite_fns: {},
      run_async_with_defer: false,
      proto_routes: []
    )
      @add_query_time_tags_fn = add_query_time_tags_fn
      @controller = controller
      @custom_tags = custom_tags
      @enabled_flags = enabled_flags
      @origin = origin
      @path_override = path_override
      @precompute_subscription_fns = precompute_subscription_fns
      @query_callback_fns = query_callback_fns
      @request = request
      @ssr_hints = ssr_hints
      @scripts = scripts
      @stats = stats
      @stylesheets = stylesheets
      @url_override = url_override
      @user = user
      @variable_overwrite_fns = variable_overwrite_fns
      @run_async_with_defer = run_async_with_defer
      @app_name = T.let(app_name || controller.class.react_bundle_name || controller.controller_name.dasherize, String)
      # Collapse leading slashes/backslashes to prevent protocol-relative URL open redirect (github/issues#20920)
      @initial_path = T.let((path_override || @request.fullpath).sub(%r{\A[/\\]+}, "/"), String)

      @embedded_data = T.let({
        payload: html_payload(payload || {}),
        title: title,
        meta: {
          title: title
        }
      }, T::Hash[Symbol, T.untyped])
      # Tell the client which route ids carry proto3-JSON payloads so it
      # decodes them with the matching schema on first paint.
      @embedded_data[:meta][:protoRoutes] = proto_routes if proto_routes.any?
    end

    sig do
      params(
        block: T.proc.params(
          ssr_response: T.untyped,
          embedded_data: T::Hash[Symbol, T.untyped],
          attempted_ssr: T::Boolean
        ).returns(T.untyped)
      ).returns(T.untyped)
    end
    def render(&block)
      @request.env[GitHub::TaggingHelper::PROCESS_REQUEST_REACT_TYPE] = "html"

      ssr_renderer.render do |ssr_response, attempted_ssr|
        Rails.logger.info "Rendered React app #{@app_name} with SSR: #{attempted_ssr}, Path: #{@initial_path}, User-Agent: #{@request.user_agent}, Status: #{ssr_response.status}"
        yield ssr_response, @embedded_data, attempted_ssr
      end
    end

    private

    sig { returns(React::SsrRenderer) }
    def ssr_renderer
      React::SsrRenderer.new(
        add_query_time_tags_fn: @add_query_time_tags_fn,
        controller: @controller,
        enabled_flags: @enabled_flags,
        origin: @origin,
        path_override: @path_override,
        precompute_subscription_fns: @precompute_subscription_fns,
        query_callback_fns: @query_callback_fns,
        request: @request,
        run_async_with_defer: @run_async_with_defer,
        ssr_payload: {
          name: @app_name,
          path: @initial_path,
          url: @url_override || @request.url,
          data: @embedded_data,
          scripts: @scripts,
          stylesheets: @stylesheets,
        },
        ssr_hints: @ssr_hints,
        disable_ssr: false,
        force_ssr: true,
        skip_preloading_and_ssr: false,
        stats: @stats,
        tags: [
          "app_name:#{@app_name}",
          "turbo_type:#{@controller.turbo_type || "none"}",
        ].concat(@custom_tags),
        user: @user,
        variable_overwrite_fns: @variable_overwrite_fns,
        data_router_enabled: true
      )
    end

    sig { params(payload: T.any(T.proc.returns(T::Hash[Symbol, T.untyped]), T::Hash[Symbol, T.untyped])).returns(T.nilable(T::Hash[T.untyped, T.untyped])) }
    def html_payload(payload)
      # TODO: cleanup Proc payloads
      parsed_payload = if payload.is_a?(Proc)
        payload.call
      else
        payload
      end

      add_payload_csrf_tokens(parsed_payload)
    end

    sig { params(payload: T::Hash[Symbol, T.untyped]).returns(T.nilable(T::Hash[T.untyped, T.untyped])) }
    def add_payload_csrf_tokens(payload)
      csrf_tokens = @controller.csrf_tokens
      payload[:csrf_tokens] = csrf_tokens unless csrf_tokens.nil? || @request.headers["access-control-allow-origin"]
      payload
    end
  end
end
