class QueriesController < ApplicationController
  rescue_from Rack::Timeout::RequestTimeoutException, with: :handle_timeout

  before_action :set_graphql_timeout, only: [:create]
  before_action :show_backtraces, only: [:create]
  before_action :validate, only: [:create]

  def create
    q = GraphQL::Query.new(API::Schema, query, variables: variables)
    result =
      if q.mutation?
        ActiveRecord::Base.connected_to(role: :writing) do
          q.result
        end
      else
        ActiveRecord::Base.connected_to(role: :reading) do
          q.result
        end
      end
    render json: result
  rescue => e
    unless e.is_a?(Rack::Timeout::RequestTimeoutException)
      Instrument.increment("graphql.query.unhandled_error",
        error_class: e.class.name,
        operation_name: q ? (q.operation_name || "anonymous") : "unknown",
        mutation: q&.mutation? || false,
      )
    end
    raise
  end

  private

  def validate
    unless query.present?
      render json: { error: "'query' is required." }, status: :unprocessable_entity
    end
  end

  def query
    request.parameters[:query]
  end

  def variables
    case request.parameters[:variables]
    when Hash, ActionController::Parameters
      request.parameters[:variables]&.to_hash || {}
    when String
      JSON.parse(request.parameters[:variables]) || {}
    else
      {}
    end
  rescue JSON::ParserError
    {}
  end

  def set_graphql_timeout
    if Rails.application.fast_api_host?
      rt_info = request.env["rack-timeout.info"]
      if rt_info
        # Lower the Rack::Timeout for GraphQL requests to match the monolith client timeout.
        # Non-GraphQL endpoints (Twirp, etc.) keep the higher API_RACK_TIMEOUT.
        rt_info.timeout = DependencyGraph::Application::GRAPHQL_RACK_TIMEOUT
      end
    end
  end

  def show_backtraces
    request.env["action_dispatch.show_detailed_exceptions"] = true
  end

  def handle_timeout
    Instrument.increment("graphql.query.timeout")
    render json: {
      data: nil,
      errors: [{ message: "Request timed out" }]
    }, status: :ok
  end
end
