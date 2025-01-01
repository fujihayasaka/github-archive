# typed: true
# frozen_string_literal: true

class Memexes::ColumnsController < Memexes::Controller
  include MemexesHelper
  include ApplicationController::VerifiedFetchDependency

  # cluster dependencies analysis will be enabled for this non-get requests
  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "Memexes::ColumnsController#create",
    "Memexes::ColumnsController#destroy",
    "Memexes::ColumnsController#update"
  ]

  # global critical dependencies, needed for all actions
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Memex

  before_action :login_required, except: [:index, :show]
  before_action :disable_color_modes
  before_action :require_memex_feature_enabled
  before_action :require_this_memex
  before_action :user_has_read_access, only: [:index, :show]
  before_action :user_has_write_access, only: [:update, :destroy, :create]
  before_action :support_backwards_compatible_settings_parameters, only: [:update]
  before_action :require_this_column, only: [:show, :update, :destroy]
  before_action :require_verified_email, only: [:create]
  before_action :require_positive_position, only: [:create]
  before_action :require_valid_data_type, only: [:create]
  before_action :require_user_defined_column, only: [:destroy]
  before_action :set_client_uid

  allow_verified_fetch only: [:create, :update, :destroy]

  depends_on_clusters ApplicationRecord::Collab, only: [:show]
  depends_on_clusters ApplicationRecord::Collab,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Repositories, only: [:index]
  depends_on_clusters ApplicationRecord::Iam,
    ApplicationRecord::Ballast,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql2, only: [:index], optional: true

  # Required for determining outside collaborator access to issue_types feature
  # This allows us to determine if the user has access to create a type column
  # We can remove this dependency when issue_types is globally enabled
  depends_on_clusters ApplicationRecord::Repositories, only: [:create, :update]

  def index
    ids = underscored_params[:column_ids]
    return head(:unprocessable_entity) unless ids

    columns = ids.map { |id| this_memex.find_column_by_name_or_id(id) }.compact

    render_columns_with_items(columns: columns, cap_filter: cap_filter)
  end

  def show
    render_columns(columns: this_column, status: :ok)
  end

  depends_on_clusters ApplicationRecord::Collab, only: [:create]

  def create
    column = this_memex.add_user_defined_column(
      name: create_memex_column_params[:name],
      data_type: create_memex_column_params[:data_type].underscore,
      position: create_memex_column_params[:position],
      settings: create_memex_column_params[:settings].presence,
      creator: current_user
    )

    if column.valid? && column.persisted?
      render_columns(columns: column, status: :created)
    else
      render(json: { errors: column.errors.full_messages }, status: :unprocessable_entity)
    end
  end

  depends_on_clusters ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    ApplicationRecord::IssuesPullRequests, only: [:update]

  def update
    shown = !this_column.visible && update_memex_column_params.fetch(:visible, nil)

    if this_column && updating_column_priority?
      # tech debt: when position column changes to be bigint, replace this block with GitHub::Prioritizable logic
      success = reprioritize_this_column
      unless success
        return render_json_error(
          error: "Custom field position couldn't be saved.",
          status: :service_unavailable
        )
      end
    end

    success = this_memex.update_column(
      this_column,
      name: update_memex_column_params[:name],
      visible: update_memex_column_params[:visible],
      settings: update_memex_column_params[:settings],
    )

    if success && shown
      render_columns_with_items(columns: this_column)
    elsif success
      render_columns(columns: this_column)
    else
      render(json: { errors: this_column.errors.full_messages }, status: :unprocessable_entity)
    end
  end

  depends_on_clusters ApplicationRecord::Collab, only: [:destroy]

  def destroy
    head(this_memex.delete_column(this_column) ? :no_content : :unprocessable_entity)
  end

  private

  def create_memex_column_params
    underscored_params.require(:memex_project_column).permit(
      :name,
      :data_type,
      :position,
      settings: [
        options: [
          :name,
          :color,
          :description
        ],
        configuration: [
          :start_day,
          :duration,
          iterations: [
            :title,
            :start_date,
            :duration
          ],
          completed_iterations: [
            :title,
            :start_date,
            :duration
          ]
        ]
      ]
    )
  end

  def update_memex_column_params # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @update_memex_column_params if defined?(@update_memex_column_params)

    @update_memex_column_params = underscored_params.permit(
      :org,
      :memex_id,
      :memex_number,
      :memex_project_column_id,
      :name,
      :visible,
      :position,
      :previous_memex_project_column_id,

      # These top-level `width` and `options` parameters are deprecated.
      # Clients should prefer the `settings.*` parameters.
      :width,
      options: [
        :name,
        :color,
        :description
      ],

      settings: [
        :width,
        options: [
          :id,
          :name,
          :color,
          :description
        ],
        configuration: [
          :start_day,
          :duration,
          iterations: [
            :id,
            :title,
            :start_date,
            :duration
          ],
          completed_iterations: [
            :id,
            :title,
            :start_date,
            :duration
          ]
        ],
        progress_configuration: [
          :color,
          :hide_numerals,
          :variant
        ],
      ]
    )
  end

  def support_backwards_compatible_settings_parameters
    top_level_settings = update_memex_column_params.slice(:width, :options)
    return if top_level_settings.empty?

    # Provide backwards-compatible support for a top-level `width` key by
    # nesting its value underneath the top-level `settings` key.
    update_memex_column_params[:settings] ||= ActionController::Parameters.new.permit(
      :width,
      options: []
    )
    update_memex_column_params[:settings].reverse_merge!(top_level_settings)
  end

  def require_positive_position
    position = if update_request?
      update_memex_column_params[:position]
    else
      create_memex_column_params[:position]
    end

    if position && position.to_i < 1
      render_json_error(error: "Position must be a positive integer", status: :unprocessable_entity)
    end
  end

  def require_this_column
    render_404 unless this_column
  end

  def require_valid_data_type
    data_type = create_memex_column_params[:data_type]
    unless allowed_generic_data_types.include?(data_type)
      render_json_error(
        error: "You must provide one of the following supported data_types: #{allowed_generic_data_types.join(", ")}",
        status: :unprocessable_entity,
      )
    end
  end

  def require_user_defined_column
    return unless this_column

    unless this_column.user_defined?
      render_json_error(
        error: "You cannot perform this operation on a system-defined column.",
        status: :unprocessable_entity
      )
    end
  end

  def updating_column_priority?
    update_memex_column_params.has_key?(:previous_memex_project_column_id)
  end

  def reprioritize_this_column
    prioritization_options = previous_column ? { after: previous_column } : { position: :top }
    success = this_column.memex_project.save_column_with_priority(this_column, **prioritization_options)
    yield if !success && block_given?
    success
  end

  def this_column # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @this_column ||= \
      this_memex.find_column_by_name_or_id(underscored_params[:memex_project_column_id])
  end

  def previous_column # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @previous_column if defined?(@previous_column)
    return nil unless update_memex_column_params[:previous_memex_project_column_id].is_a?(Numeric)
    @previous_column = this_memex
      .memex_project_columns
      .find_by(id: update_memex_column_params[:previous_memex_project_column_id])
  end

  def update_request?
    action_name == "update"
  end
end
