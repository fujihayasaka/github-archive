# typed: true
# frozen_string_literal: true

class Memexes::ChartsController < Memexes::Controller
  include ApplicationController::VerifiedFetchDependency

  before_action :login_required, except: [:index]
  before_action :disable_color_modes
  before_action :require_memex_feature_enabled
  before_action :require_this_memex
  before_action :require_this_chart, only: [:update, :destroy]
  before_action :user_has_read_access, only: [:index]
  before_action :user_has_write_access, except: [:index]
  before_action :require_verified_email, except: [:index]
  before_action :set_client_uid

  allow_verified_fetch only: [:create, :update, :destroy]

  # cluster dependencies analysis will be enabled for this non-get requests
  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "Memexes::ChartsController#create",
    "Memexes::ChartsController#update",
    "Memexes::ChartsController#destroy"
  ]

  # global critical dependencies, needed for all actions
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Memex,
    ApplicationRecord::Collab

  depends_on_clusters ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    only: [:index]

  def index
    render(json: { charts: this_memex.supported_charts.map(&:to_hash) })
  end

  depends_on_clusters ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    only: [:create]

  def create
    chart = this_memex.charts.create(
      creator: current_user,
      **chart_params,
    )
    if chart.valid? && chart.persisted?
      render(json: { chart: chart.to_hash }, status: :created)
    else
      render(json: { errors: chart.errors.full_messages }, status: :unprocessable_entity)
    end
  end

  depends_on_clusters ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    only: [:update]

  def update
    if this_chart.update(**chart_params)
      render(json: { chart: this_chart.to_hash })
    else
      render(json: { errors: this_chart.errors.full_messages }, status: :unprocessable_entity)
    end
  end

  depends_on_clusters ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    only: [:destroy]

  def destroy
    if this_chart.destroy
      head :no_content
    elsif this_chart.errors.any?
      render(json: { errors: this_chart.errors.full_messages }, status: :unprocessable_entity)
    else
      head :bad_request
    end
  end

  private def require_this_chart
    render_404 unless this_chart
  end

  private def this_chart # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @this_chart if defined?(@this_chart)
    @this_chart = this_memex.charts.find_by(number: underscored_params[:chart_number])
  end

  private def chart_params # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @chart_params if defined?(@chart_params)
    @chart_params = underscored_params
      .require(:chart)
      .permit(
        :name,
        configuration: {},
      )
      .merge(camel_case_configuration_params)
  end

  # We retain the camelCase names of nested configuration fields
  # which are stored as JSON.
  private def camel_case_configuration_params
    config_params = params.fetch(:chart).slice(:configuration).permit(
      configuration: {},
    )
  end
end
