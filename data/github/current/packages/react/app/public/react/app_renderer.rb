# typed: strict
# frozen_string_literal: true

module React
  class AppRenderer
    sig { returns(String) }
    attr_reader :app_name

    sig { returns(String) }
    attr_reader :initial_path

    sig { returns(T::Hash[Symbol, T.untyped]) }
    attr_reader :locals

    sig do
      params(
        app_name: T.nilable(String),
        app_payload_generator: T.nilable(T.proc.returns(T.nilable(T::Hash[Symbol, T.untyped]))),
        controller: ApplicationController,
        custom_tags: T::Array[String],
        enabled_flags: T.nilable(T::Array[T.untyped]),
        layout_locals_generator: T.nilable(T.proc.returns(T::Hash[Symbol, T.untyped])),
        origin: T.untyped,
        path_override: T.nilable(String),
        payload: T.nilable(T.any(T.proc.returns(T::Hash[Symbol, T.untyped]), T::Hash[Symbol, T.untyped])),
        request: ActionDispatch::Request,
        ssr_hints: Alloy::SelectiveSsr::Hints,
        disable_ssr: T::Boolean,
        force_ssr: T::Boolean,
        stats: T::Hash[Symbol, T.untyped],
        title: T.nilable(String),
        user: T.nilable(User),
        add_query_time_tags_fn: T.nilable(T.proc.params(arg0: String, arg1: T::Hash[T.untyped, T.untyped]).returns(T.nilable(T::Array[String]))),
        precompute_subscription_fns: T::Hash[String, T.proc.params(arg0: T.untyped, arg1: T.untyped).returns(T.untyped)],
        query_callback_fns: T::Hash[String, T.proc.params(arg0: T.untyped, arg1: T.untyped).returns(T.untyped)],
        url_override: T.nilable(String),
        variable_overwrite_fns: T::Hash[Symbol, T.proc.params(path_variables: T::Hash[T.untyped, T.untyped]).returns(T.untyped)],
        run_async_with_defer: T::Boolean,
        data_router_enabled: T.nilable(T::Boolean)
      ).void
    end
    def initialize(
      app_name:,
      app_payload_generator:,
      controller:,
      custom_tags:,
      enabled_flags:,
      layout_locals_generator:,
      origin:,
      path_override:,
      payload:,
      request:,
      ssr_hints:,
      disable_ssr:,
      force_ssr:,
      stats:,
      title:,
      user:,
      add_query_time_tags_fn: nil,
      precompute_subscription_fns: {},
      query_callback_fns: {},
      url_override: nil,
      variable_overwrite_fns: {},
      run_async_with_defer: false,
      data_router_enabled: false
    )
      @add_query_time_tags_fn = add_query_time_tags_fn
      @app_payload_generator = app_payload_generator
      @controller = controller
      @custom_tags = custom_tags
      @enabled_flags = enabled_flags
      @layout_locals_generator = layout_locals_generator
      @origin = origin
      @path_override = path_override
      @precompute_subscription_fns = precompute_subscription_fns
      @query_callback_fns = query_callback_fns
      @request = request
      @ssr_hints = ssr_hints
      @disable_ssr = disable_ssr
      @force_ssr = force_ssr
      @stats = stats
      @url_override = url_override
      @user = user
      @variable_overwrite_fns = variable_overwrite_fns
      @run_async_with_defer = run_async_with_defer
      @app_name = T.let(app_name || controller.class.react_bundle_name || controller.controller_name.dasherize, String)
      @initial_path = T.let(path_override || @request.fullpath, String)
      @data_router_enabled = data_router_enabled

      @locals = T.let(@layout_locals_generator&.call || {}, T::Hash[Symbol, T.untyped])
      @embedded_data = T.let({
        payload: html_payload(payload || {}),
        title: title,
        appPayload: generate_app_payload
      }, T::Hash[Symbol, T.untyped])

      if @data_router_enabled
        @embedded_data[:meta] = {
          title: title,
        }
      end
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
        embedded_data_with_queries = add_preloaded_queries(ssr_response.preloaded_queries)


        @stats[:errors_in_preloaded_queries] = [] unless @stats[:errors_in_preloaded_queries]
        @stats[:errors_in_preloaded_queries].concat(add_query_errors(embedded_data_with_queries))

        yield ssr_response, embedded_data_with_queries, attempted_ssr
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
        },
        ssr_hints: @ssr_hints,
        disable_ssr: @disable_ssr,
        force_ssr: @force_ssr,
        stats: @stats,
        tags: [
          "app_name:#{@app_name}",
          "turbo_type:#{@controller.turbo_type || "none"}",
        ].concat(@custom_tags),
        user: @user,
        variable_overwrite_fns: @variable_overwrite_fns,
        data_router_enabled: @data_router_enabled
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

    sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
    def generate_app_payload
      app_payload = @app_payload_generator.call if @app_payload_generator
      unless @controller.client_feature_flags.nil?
        app_payload ||= {}
        app_payload[:enabled_features] = @controller.client_feature_flags&.merge(app_payload[:enabled_features] || {})
      end

      app_payload
    end

    sig { params(preloaded_queries: T.untyped).returns(T::Hash[Symbol, T.untyped]) }
    def add_preloaded_queries(preloaded_queries)
      if preloaded_queries && preloaded_queries.length > 0
        @embedded_data[:payload] ||= {}
        @embedded_data[:payload][:preloadedQueries] = preloaded_queries
      end

      @embedded_data
    end

    sig { params(embedded_data_with_queries: T::Hash[Symbol, T.untyped]).returns(T::Array[T::Hash[String, T.untyped]]) }
    def add_query_errors(embedded_data_with_queries)
      errors_in_preloaded_queries = []
      preloaded_queries = embedded_data_with_queries.dig(:payload, :preloadedQueries)
      if preloaded_queries
        preloaded_queries.each do |query|
          errors = query.dig(:result, :errors)
          if errors
            query_name = query.dig(:queryName)
            errors.each do |error|
              errors_in_preloaded_queries << {
                query: query_name,
                type: error.dig(:type),
                message: error.dig(:message),
                path: error.dig(:path) ? error.dig(:path).join(".") : nil,
                line: error.dig(:extensions, :ruby_backtrace)&.first,
              }
            end
          end
        end
      end
      errors_in_preloaded_queries
    end
  end
end
