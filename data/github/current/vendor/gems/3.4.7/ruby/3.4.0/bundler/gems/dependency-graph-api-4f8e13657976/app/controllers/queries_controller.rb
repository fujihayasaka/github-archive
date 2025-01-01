class QueriesController < ApplicationController
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

  def show_backtraces
    request.env["action_dispatch.show_detailed_exceptions"] = true
  end
end
