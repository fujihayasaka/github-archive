# typed: true
# frozen_string_literal: true

class WebSocketsController < ApplicationController
  # must come before login_required to prevent queries for the user
  include GitHub::RateLimitedRequest

  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  before_action :login_required

  # limit requests for both endpoints to 100 per minute
  rate_limit_requests(max: :web_sockets_rate_limit, ttl: 1.minute, key: :rate_limit_key_by_ip, if: :request_is_rate_limited?)

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
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

  def web_sockets_rate_limit
    # We need to add 1 here otherwise we will rate limit on the Nth request, where N is the limit.
    # For example, if the limit is 100, we will rate limit on the 100th request.
    # We want to rate limit on the 101st request, so we add 1.
    GitHub.web_sockets_rate_limit + 1
  end

  def request_is_rate_limited?
    GitHub.web_sockets_rate_limit > 0
  end
end
