# typed: true
# frozen_string_literal: true

class Settings::GravatarStatusesController < ApplicationController
  include Settings::ControllerMethods

  before_action :login_required
  before_action :ensure_gravatar_enabled

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    only: [:show]

  GRAVATAR_BASE_URL = "https://en.gravatar.com"

  def show
    gravatar_url = "#{GRAVATAR_BASE_URL}/#{current_user.gravatar_id}.json"

    gravatar_response = faraday.get(gravatar_url, { "Accept" => "application/json" })
    render json: { has_gravatar: gravatar_response.success? }
  rescue Faraday::ConnectionFailed, Faraday::TimeoutError
    render json: { has_gravatar: false }
  end

  private

  def faraday
    GitHub::FaradayClient::External.new do |c|
      c.adapter Faraday.default_adapter
    end
  end

  def ensure_gravatar_enabled
    return render_404 unless GitHub.gravatar_enabled?
  end
end
