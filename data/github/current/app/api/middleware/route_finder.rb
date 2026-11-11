# typed: true
# frozen_string_literal: true

class Api::Middleware::RouteFinder

  def initialize(app)
    @current_app = app
    @top_app = get_top_level_app(app)
  end

  def call(env)
    request = Rack::Request.new(env)

    # routes returns a hash keyed by request method with values as an array of arrays
    # for each endpoint that corresponds to that method
    # e.g.
    # {
    #   "GET" => [
    #     [/\A\/licenses\z/, [], [], #<Proc:0x007ffd592c22f8>],
    #     [/\A\/licenses\/([^\/?#]+)\z/, ["license"], [], #<Proc:0x007ffd592bbb10>]
    #   ],
    #   "HEAD" => [
    #     [/\A\/licenses\z/, [], [], #<Proc:0x007ffd592c1600>],
    #     [/\A\/licenses\/([^\/?#]+)\z/, ["license"], [], #<Proc:0x007ffd592bb110>]
    #   ]
    # }
    routes_by_method = @top_app.class.routes || {}
    routes = routes_by_method[request.request_method] || []
    request_path = env[GitHub::Routers::Api::PATH_INFO] || request.path
    route_info = routes.find { |pattern, _, _, _| pattern.match(request_path) }
    route_path = route_info&.first
    # Twirp requests are routed with a `/*`,
    # but use the actual `request_path` because it includes
    # a final segment that names the rpc operation.
    # The request path never includes parameters, so use it verbatim here.
    if route_path && @top_app.is_a?(Api::Internal::Twirp)
      route_path = request_path
    end

    if route_path.present?
      named_route = "#{request.request_method} #{route_path}"

      env["github.api.route"] = named_route
      OpenTelemetry::Instrumentation::Rack.current_span&.name = named_route
    end

    # If the request was previewed by the gateway, compare 404 outcomes
    # TODO: Remove this when the gateway is no longer in preview mode.
    if GitHub.server_site == "gc-cus-02" && FeatureFlag.vexi.enabled?(:gateway_preview_not_found_science, default: false)
      GitHub::Experiment.new "gateway_preview_not_found" do |e|
        e.run_if { request.env["HTTP_X_GITHUB_GATEWAY_ROUTING_RESULT"].present? }

        e.context({
          request_path: request_path,
          request_method: request.request_method,
          request_id: env["HTTP_X_GITHUB_REQUEST_ID"],
          backend_route: request.env["HTTP_X_GITHUB_GATEWAY_ROUTING_BACKEND_ROUTE"]
        })

        # OPTIONS requests are not part of the Sinatra handlers, but are handled unconditionally by
        # Api::Middleware::Cors so we can mark them as "false" here to indicate they will be handled
        e.use do
          if request.request_method == "OPTIONS"
            false
          else
            route_path.blank?
          end
        end
        e.try { request.env["HTTP_X_GITHUB_GATEWAY_ROUTING_RESULT"] == "not_found" }
        e.ignore do |_, _|
          # This is to avoid false positives in the experiment when the request path is not a valid deployment ID (non-integers).
          if request_path =~ %r{\A/repositories/\d+/deployments/([^/]+)/statuses\z}
            deployment_id = $1
            deployment_id !~ /\A\d+\z/ # Ignore if the deployment ID is not a number
          elsif request_path =~ %r{\A/repositories/\d+/actions/runs/([^/]+)(/(artifacts|jobs|logs))?\z}
            run_id = $1
            run_id !~ /\A\d+\z/ # Ignore if the run ID is not a number
          elsif request_path.start_with?("/repositories/0/commits/")
            true
          else
            false
          end
        end
      end.run
    end

    if route_path.present? && GitHub.server_site == "gc-cus-02" && FeatureFlag.vexi.enabled?(:gateway_preview_backend_route_science, default: false)
      GitHub::Experiment.new "gateway_backend_route_validation" do |e|
        e.run_if { request.env["HTTP_X_GITHUB_GATEWAY_ROUTING_RESULT"].present? }

        e.context({
          request_path: request_path,
          request_method: request.request_method,
          request_id: env["HTTP_X_GITHUB_REQUEST_ID"],
        })

        e.use { route_path.to_s }
        e.try { request.env["HTTP_X_GITHUB_GATEWAY_ROUTING_BACKEND_ROUTE"] }
        e.ignore do |_, _|
          if request_path.start_with?("/repositories/0/commits/") || request_path.match?(/\/commits\/\//)
            true
          else
            false
          end
        end
      end.run
    end

    @current_app.call(env)
  end

  private

  # Private: Recursively searches for the app instance that
  # doesn't have the @app ivar set, which is the top level
  # instance (aka the controller that will eventually call the
  # endpoint)
  #
  # app - The instance of app, which is likely an
  # instance of next layer of middleware
  #
  # Examples
  #
  #   top_level_app(@app)
  #   # => #<Api::Licenses:0x007f9c3f9c2e70 @app=nil>
  #
  # Returns the top lovel app instance
  def get_top_level_app(app)
    until app.instance_variable_get(:@app).nil?
      app = app.instance_variable_get(:@app)
    end
    app
  end
end
