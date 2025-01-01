# typed: true
# frozen_string_literal: true

class Memexes::ViewsController < Memexes::Controller
  include ApplicationController::VerifiedFetchDependency

  preload_features [:org_feature_helper]

  # cluster dependencies analysis will be enabled for this non-get requests
  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "Memexes::ViewsController#create",
    "Memexes::ViewsController#destroy",
    "Memexes::ViewsController#update"
  ]

  # global critical dependencies, needed for all actions
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Memex,
    ApplicationRecord::Collab

  before_action :login_required
  before_action :disable_color_modes
  before_action :require_memex_feature_enabled
  before_action :require_this_memex
  before_action :user_has_write_access
  before_action :require_verified_email, only: [:create]
  before_action :set_client_uid

  allow_verified_fetch only: [:create, :update, :destroy]

  def create
    view = this_memex.memex_project_views.build(
      creator: current_user,
      **view_params.except(*non_model_params)
    )

    if view.valid?
      prioritization_options = {}
      if view_params.has_key?(:previous_memex_project_view_id)
        prioritization_options = previous_view_for_create ? { after: previous_view_for_create } : { position: :top }
      end
      this_memex.save_view_with_priority!(view, **prioritization_options)
    end

    if view.persisted?
      render(json: { view: view.to_hash }, status: :created)
    else
      render(json: { errors: view.errors.full_messages }, status: :unprocessable_entity)
    end
  end

  def update
    if this_view && view_params_for_update[:previous_memex_project_view_id]
      begin
        reprioritize_view
      rescue GitHub::Prioritizable::Context::LockedForRebalance
        return render_json_error(
          error: "This project view is undergoing maintenance.",
          status: :service_unavailable
        )
      end
    end

    if this_view.update(**view_params_for_update.except(*non_model_params))
      render(json: { view: this_view.to_hash }, status: :ok)
    else
      render(json: { errors: this_view.errors.full_messages }, status: :unprocessable_entity)
    end
  end

  def destroy
    if this_view.destroy
      head :no_content
    elsif this_view.errors.any?
      render(json: { errors: this_view.errors.full_messages }, status: :unprocessable_entity)
    else
      head :bad_request
    end
  end

  private def reprioritize_view
    prioritization_options = previous_view ? { after: previous_view } : { position: :top }
    success = this_view.memex_project.save_view_with_priority!(this_view, **prioritization_options)
    yield if !success && block_given?
    success
  end

  # These are attributes that maybe passed in the payload but
  # are not model parameters and should not be persisted
  private def non_model_params
    [:previous_memex_project_view_id]
  end

  private def view_params # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @view_params if defined?(@view_params)

    @view_params = underscored_params.fetch(:view, {}).permit(
      :name,
      :filter,
      :layout,
      :previous_memex_project_view_id,
      group_by: [],
      vertical_group_by: [],
      slice_by: {},
      visible_fields: [],
      sort_by: [sort: []],
      aggregation_settings: [:hide_items_count, sum: []],
      layout_settings: [table: {}, board: {}, roadmap: {}],
    ).with_defaults(
      name: nil,
      filter: nil,
      layout: nil,
      previous_memex_project_view_id: nil,
      sort_by: [],
      group_by: [],
      vertical_group_by: [],
      slice_by: {},
      visible_fields: [],
      aggregation_settings: { hide_items_count: false, sum: [] },
      layout_settings: {},
    )

    # Since strong params don't play nicely with nested arrays [https://github.com/github/github/pull/181210]
    # we explictly pass through these values, even after declaring them in the permit method above
    @view_params[:sort_by] = underscored_params[:view][:sort_by].to_a

    @view_params
  end

  private def view_params_for_update # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @view_params_for_update if defined?(@view_params_for_update)

    @view_params_for_update = underscored_params.require(:view).permit(
      :name,
      :filter,
      :layout,
      :previous_memex_project_view_id,
      group_by: [],
      visible_fields: [],
      sort_by: [sort: []],
      vertical_group_by: [],
      slice_by: {},
      aggregation_settings: [:hide_items_count, sum: []],
      layout_settings: [table: {}, board: {}, roadmap: {}],
    ).with_defaults(
      name: nil,
      filter: nil,
      layout: nil,
      previous_memex_project_view_id: nil,
      sort_by: [],
      group_by: [],
      visible_fields: [],
      vertical_group_by: [],
      slice_by: {},
      aggregation_settings: { hide_items_count: false, sum: [] },
      layout_settings: {},
    )

    # Since strong params don't play nicely with nested arrays [https://github.com/github/github/pull/181210]
    # we explictly pass through these values, even after declaring them in the permit method above
    @view_params_for_update[:sort_by] = underscored_params[:view][:sort_by].to_a

    @view_params_for_update
  end

  private def this_view # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @this_view if defined?(@this_view)
    @this_view = this_memex.memex_project_views.find_by!(number: underscored_params.require(:view_number))
  end

  # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
  private def previous_view_for_create
    return @previous_view_for_create if defined?(@previous_view_for_create)
    @previous_view_for_create = view_params[:previous_memex_project_view_id].presence && this_memex
      .memex_project_views
      .find_by(id: view_params[:previous_memex_project_view_id])
  end
  # rubocop:enable GitHub/ControllersShouldUseMemoizeForMemoization

  # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
  private def previous_view
    return @previous_view if defined?(@previous_view)
    @previous_view = this_memex
      .memex_project_views
      .find_by(id: view_params_for_update[:previous_memex_project_view_id])
  end
  # rubocop:enable GitHub/ControllersShouldUseMemoizeForMemoization
end
