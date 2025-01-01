# typed: true
# frozen_string_literal: true

class Api::Internal::MarketplaceAnalytics < Api::Internal

  def login_from_api_auth; end

  use Rack::Auth::Basic, "Protected Area" do |_username, password|
    (!ENV["INTERNAL_API_MARKETPLACE_PASSWORD"].blank? &&
    SecurityUtils.secure_compare(password, ENV["INTERNAL_API_MARKETPLACE_PASSWORD"]))
  end

  # Internal API endpoint for signaling that marketplace traffic analytics are
  # ready for a given day.

  post "/internal/marketplace/traffic_analytics_ready", operation_id: :internal do
    @route_owner = "@github/marketplace-eng"
    params = receive_json(request.body.read, type: Hash)
    deliver_error!(400, message: "Parameter 'date' is required") unless date = params["date"]

    GitHub.dogstats.increment("marketplace.insights.traffic-analytics-ready")
    UpdateMarketplaceInsightsJob.enqueue(date, :traffic)

    deliver_empty status: 202
  end
end
