# typed: true
# frozen_string_literal: true

class WebSocketsController < ApplicationController
  # must come before login_required to prevent queries for the user
  include GitHub::RateLimitedRequest

  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  before_action :login_required

  # limit requests for both endpoints to 100 per minute
  rate_limit_requests(max: 100, ttl: 1.minute, key: :rate_limit_key_by_ip, if: :request_is_rate_limited?)

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    only: [:show]

  def show
    render json: {
      url: alive_web_socket_url,
      token: authenticity_token_for(alive_web_socket_path)
    }
  end

  def create
    render plain: GitHub::WebSocket.luau_url(user_session)
  end

  private

  def request_is_rate_limited?
    !GitHub.single_tenant_enterprise?
  end
end
