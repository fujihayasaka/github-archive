# typed: true
# frozen_string_literal: true

class FilterProvidersController < ApplicationController
  layout false

  before_action :ensure_query_value_present, only: [:show]
  around_action :track_request_time, only: [:index, :show]

  LOGGED_OUT_SUGGESTION_LIMIT = 25
  FILTER_SUGGESTION_LIMIT = 500

  private

  def ensure_query_value_present
    head :bad_request unless query_value.present?
  end

  def respond_payload(json)
    respond_to do |format|
      format.json do
        render json: json
      end
    end
  end

  def respond_error(status_code, message)
    respond_to do |format|
      format.json do
        render json: { error: message }, status: status_code
      end
    end
  end

  # Used for database `LIKE` queries
  memoize def like_query_value
    return "%" unless query_value.present?
    sanitize_sql_like(query_value)
  end

  def sanitize_sql_like(value)
    "%#{ActiveRecord::Base.sanitize_sql_like(value&.to_s&.strip || "")}%"
  end

  def query_value
    params[:q].to_s
  end

  def has_search_query?
    query_value.present?
  end

  def track_request_time
    tags = [
      "controller:#{controller_name}",
      "action:#{action_name}",
    ]

    track_time(metric: "filter_providers.dist.time", tags: tags) do
      yield
    end
  end

  def maximum_result_limit
    logged_in? ? FILTER_SUGGESTION_LIMIT : LOGGED_OUT_SUGGESTION_LIMIT
  end
end
