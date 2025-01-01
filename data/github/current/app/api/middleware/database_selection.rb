# typed: false
# frozen_string_literal: true

class Api::Middleware::DatabaseSelection
  include Api::App::RequestMethodHelper

  # We ignore the GraphQL api path because that will always be a POST, and we
  # can't reset the db routing token in each request, otherwise the next consecutive request
  # could, wrongly, hit the master database.
  # Platform::Session module is responsible for doing the routing on graphql queries.
  #
  # /chunks, /code, /embeddings, /symbols accept post requests but only require read-only db access
  IGNORED_PATHS = %w(
    /chunks
    /code
    /embeddings
    /graphql
    /symbols
  )

  def initialize(app)
    @app = app
  end

  def call(env)
    GitHub.tracer.in_span("api.middleware", kind: :internal, attributes: {
      "code.namespace" => "DatabaseSelection"
    }) do |_span|
      if ignore_db_selection?(env)
        ActiveRecord::Base.connected_to(role: :reading) { @app.call(env) }
      else
        call_with_db_selection(env)
      end
    end
  end

  # Selects the appropriate database connection based on
  # the type of request.
  def call_with_db_selection(env)
    creds = Api::RequestCredentials.from_env(env)
    last_operations = DatabaseSelector::LastOperations.from_request_creds(creds)

    select_database(env, last_operations) { @app.call(env) }
  end

  def select_database(env, last_operations, &bk)
    # Default to a read operation if the request is not a write,
    # OR if the endpoint has explicitly opted in to reading from replicas.
    read_from_replicas = self.class.read_from_replicas_route?(env)
    if read_request?(env) || read_from_replicas
      GitHub::TaggingHelper.set_rest_api_read_from_replicas(env, read_from_replicas)
      DatabaseSelector.instance.read_from_database(last_operations: last_operations, called_from: :api_middleware, &bk)
    else
      DatabaseSelector.instance.track_writes(last_operations) do
        ActiveRecord::Base.connected_to(role: :writing, &bk)
      end
    end
  end

  def request_success?(status)
    status >= 200 && status < 400
  end

  def ignore_db_selection?(env)
    request = Rack::Request.new(env)
    IGNORED_PATHS.include?(request.path_info)
  end

  def self.read_from_replicas_route?(env)
    route_id = env["github.api.route"]
    return false if route_id.nil?
    return false unless Api::RouteActor.new(route_id).feature_enabled?(:rest_api_read_from_replicas)

    self.read_from_replicas_routes.include?(route_id)
  end

  def self.read_from_replicas_routes
    @read_from_replicas_routes ||= Set.new
  end

  def self.reset_read_from_replicas_routes
    @read_from_replicas_routes = nil
  end
end
