# typed: true
# frozen_string_literal: true

class WebSocketsController < ApplicationController
  # must come before login_required to prevent queries for the user
  include GitHub::RateLimitedRequest

  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  before_action :login_required

  # limit requests for both endpoints to 100 per minute
  rate_limit_requests(max: 100, ttl: 1.minute, at_limit: :at_limit, key: :rate_limit_key_by_ip)

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

  def at_limit
    GitHub.dogstats.increment("web_sockets_controller.rate_limit.reached", tags: ["action:#{action_name}"])
  end
end
