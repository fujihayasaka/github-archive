# typed: true
# frozen_string_literal: true

class MarketplaceListingInsightsController < ApplicationController

  layout "layouts/marketplace"
  stylesheet_bundle :marketplace
  stylesheet_bundle :insights

  before_action :marketplace_required
  before_action :render_404, unless: :logged_in?
  before_action :require_viewer_can_read_insights

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    ApplicationRecord::Repositories,
    only: [:visitor_graph_data]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :visitor_graph_data],
    optional: true

  VALID_PERIODS = %w(day week month alltime)

  DEFAULT_PERIOD = :week

  # Traffic stats are lower due to people with ad blockers installed. We increase the traffic stats to more accurately reflect the real traffic numbers.
  AD_BLOCKER_MULTIPLIER = 1.08

  def index
    view = create_view_model(
      Marketplace::ListingInsights::IndexPageView,
      listing: this_marketplace_listing,
      period: period_param,
    )
    render "marketplace_listing_insights/index", locals: { view: view, marketplace_listing: this_marketplace_listing }
  end

  def visitor_graph_data # rubocop:todo GitHub/UseRestfulActions
    insights = this_marketplace_listing.insights.for_period(period_param).to_a.first(100)

    graph_data = insights.map do |record|
      results = { total: (record.pageviews * AD_BLOCKER_MULTIPLIER).to_i, unique: (record.visitors * AD_BLOCKER_MULTIPLIER).to_i }

      if period_param == :alltime
        results[:bucket] = record.recorded_on.beginning_of_month.strftime("%s")
      else
        results[:bucket] = record.recorded_on.strftime("%s")
      end

      results
    end

    total_pageviews = insights.map { |x| x.pageviews }.inject(0, :+) * AD_BLOCKER_MULTIPLIER
    total_visitors = insights.map { |x| x.visitors }.inject(0, :+) * AD_BLOCKER_MULTIPLIER

    render json: { counts: graph_data, summary: { total: total_pageviews.to_i, unique: total_visitors.to_i } }.to_json
  end

  private

  def period_param
    return DEFAULT_PERIOD unless params[:period].present?

    return params[:period].to_sym if VALID_PERIODS.include? params[:period]

    DEFAULT_PERIOD
  end

  memoize def this_marketplace_listing
    Marketplace::Listing.find_by(slug: params[:listing_slug])
  end

  def target_for_conditional_access
    # rubocop:todo GitHub/SpecifyTargetForConditionalAccess
    return :no_target_for_conditional_access unless this_marketplace_listing
    # rubocop:enable GitHub/SpecifyTargetForConditionalAccess
    this_marketplace_listing.owner
  end

  def require_viewer_can_read_insights
    render_404 unless this_marketplace_listing&.can_viewer_read_insights?(current_user)
  end
end
