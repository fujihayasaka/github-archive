# typed: strict
# frozen_string_literal: true

module React
  class PartialRenderer
    sig { returns(T::Hash[Symbol, T.untyped]) }
    attr_reader :embedded_data

    sig do
      params(
        controller: ApplicationController,
        name: String,
        origin: T.untyped,
        props: T.nilable(T.any(T::Struct, T::Hash[Symbol, T.untyped])),
        request: ActionDispatch::Request,
        ssr_hints: Alloy::SelectiveSsr::Hints,
        disable_ssr: T::Boolean,
        force_ssr: T::Boolean,
        user: T.nilable(User),
      ).void
    end
    def initialize(
      controller:,
      name:,
      origin:,
      props:,
      request:,
      ssr_hints:,
      disable_ssr:,
      force_ssr:,
      user:
    )
      @controller = controller
      @name = name
      @origin = origin
      @props = props
      @request = request
      @ssr_hints = ssr_hints
      @disable_ssr = disable_ssr
      @force_ssr = force_ssr
      @user = user

      @embedded_data = T.let({
        props: @props
      }, T::Hash[Symbol, T.untyped])

      @ssr_renderer_instance = T.let(nil, T.nilable(React::SsrRenderer))
    end

    # Kicks off the Alloy SSR request asynchronously, returns self for chaining.
    sig { returns(T.self_type) }
    def start_async
      @ssr_renderer_instance = ssr_renderer
      @ssr_renderer_instance.start_async_request
      self
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
      renderer = @ssr_renderer_instance || ssr_renderer
      renderer.render do |ssr_response, attempted_ssr|
        yield ssr_response, @embedded_data, attempted_ssr
      end
    end

    private

    sig { returns(React::SsrRenderer) }
    def ssr_renderer
      React::SsrRenderer.new(
        controller: @controller,
        origin: @origin,
        request: @request,
        ssr_payload: {
          name: @name,
          url: @request.url,
          data: @embedded_data,
        },
        ssr_hints: @ssr_hints,
        disable_ssr: @disable_ssr,
        force_ssr: @force_ssr,
        skip_preloading_and_ssr: false,
        skip_query_preloading: true,
        tags: ["name:#{@name}"],
        user: @user,
      )
    end
  end
end
