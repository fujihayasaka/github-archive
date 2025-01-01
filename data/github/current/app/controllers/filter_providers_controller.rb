# typed: true
# frozen_string_literal: true

class FilterProvidersController < ApplicationController
  layout false

  before_action :login_required
  before_action :ensure_query_value_present, only: [:show]
  around_action :track_request_time, only: [:index, :show]

  STANDARD_RESULT_LIMIT = 25
  LARGE_RESULT_LIMIT = 500

  private

  def ensure_query_value_present
    return head :bad_request unless query_value.present?
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
      "large_payloads_enabled:#{large_payloads_enabled?}",
    ]

    track_time(metric: "filter_providers.dist.time", tags: tags) do
      yield
    end
  end

  memoize def large_payloads_enabled?
    return false unless logged_in?
    current_user.feature_enabled?(:filter_prefetch_suggestions)
  end

  def maximum_result_limit
    large_payloads_enabled? ? LARGE_RESULT_LIMIT : STANDARD_RESULT_LIMIT
  end
end
