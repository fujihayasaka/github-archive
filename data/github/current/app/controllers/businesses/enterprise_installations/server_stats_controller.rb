# typed: true
# frozen_string_literal: true

class Businesses::EnterpriseInstallations::ServerStatsController < Businesses::BusinessController
  include EnterpriseServerStatsHelper
  include ReactHelper

  before_action :business_owner_required
  before_action :server_stats_check
  before_action :ensure_valid_stat_key, only: [:show]
  before_action :ensure_valid_time_period, only: [:show]

  self.react_bundle_name = "enterprise-server-stats"

  stylesheet_bundle :orgs

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities

  depends_on_clusters ApplicationRecord::Copilot,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:index]

  def index
    render "businesses/settings/enterprise_installations/server_stats", locals: {
      server_results: server_results,
      selected_server: selected_server,
      time_period: time_period
    }
  end

  def show
    stats = chart_from_usage_metrics(s4_metrics, stat_key, selected_server, time_period)

    render json: { data: camelize_stat(stats), meta: { period: time_period, server: selected_server } }
  end

  private

  def camelize_stat(stat)
    # Prepare the charts for JavaScript; the underlying chart web component requires camelCase keys
    stat.deep_transform_keys { |key| key.is_a?(Symbol) ? key.to_s.camelize(:lower) : key }
  end

  memoize def s4_metrics
    export_data = this_business.s4_usage_metrics
    JSON.parse(export_data[:blob])
  end

  memoize def selected_server
    @selected_server = params.fetch(:server, server_results.first.first)
  end

  def server_stats_check
    render_404 unless this_business&.feature_enabled?(:server_stats_graphs) && this_business&.has_s4_stats?
  end

  memoize def server_results
    export_data = this_business.s4_usage_metrics
    JSON.parse(export_data[:blob]).map { |obj| [obj["server_id"], obj["host_name"]] }.to_h
  end

  memoize def stat_key
    @stat_key = params[:stat]
  end

  memoize def time_period
    @time_period = params[:period] if TIME_PERIOD_KEYS.include?(params[:period])
    @time_period ||= "year"
  end

  def ensure_valid_stat_key
    head(:not_found) unless STAT_KEYS.include?(params[:stat])
  end

  def ensure_valid_time_period
    # time period is not required, but if set, it must be valid
    head(:bad_request) unless params[:period].nil? || TIME_PERIOD_KEYS.include?(params[:period])
  end
end
