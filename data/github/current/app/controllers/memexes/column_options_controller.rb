# typed: true
# frozen_string_literal: true

class Memexes::ColumnOptionsController < Memexes::Controller
  include MemexesHelper
  include ApplicationController::VerifiedFetchDependency

  before_action :login_required
  before_action :disable_color_modes
  before_action :require_memex_feature_enabled
  before_action :require_this_memex
  before_action :require_this_column
  before_action :user_has_write_access
  before_action :require_positive_position, only: [:create, :update]
  before_action :require_valid_data_type
  before_action :set_client_uid

  allow_verified_fetch only: [:create, :update, :destroy]

  # cluster dependencies analysis will be enabled for this non-get requests
  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "Memexes::ColumnOptionsController#create",
    "Memexes::ColumnOptionsController#update",
    "Memexes::ColumnOptionsController#destroy"
  ]

  # global critical dependencies, needed for all actions
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Memex

  depends_on_clusters ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    only: [:create]

  def create
    position = option_params[:position].to_i - 1

    column_settings = this_column_settings
    column_settings.add_option(name: option_params[:name], color: option_params[:color], description: option_params[:description], position: position)

    if this_column.update(settings: column_settings.serialize)
      render(json: { memexProjectColumn: this_column.to_hash }, status: :created)
    else
      render(json: { errors: this_column.errors.full_messages }, status: :unprocessable_entity)
    end
  end

  depends_on_clusters ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    only: [:update]

  def update
    position = option_params[:position] ? option_params[:position].to_i - 1 : nil

    column_settings = this_column_settings
    updated = column_settings.update_option(option_params[:id], name: option_params[:name], color: option_params[:color], description: option_params[:description], position: position)

    unless updated
      return render_json_error(error: "Option not found in column settings", status: :unprocessable_entity)
    end

    if this_column.update(settings: column_settings.serialize)
      if option_params.to_hash.keys.sort == %w(id position)
        MemexProjectColumn::Interface::Indexable::Processor::LiveUpdateBroadcaster.call(
          memex_project_ids: [this_memex.id],
          timestamp: Time.now.to_i
        )
      end
      render(json: { memexProjectColumn: this_column.to_hash }, status: :created)
    else
      render(json: { errors: this_column.errors.full_messages }, status: :unprocessable_entity)
    end
  end


  depends_on_clusters ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Collab,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    only: [:destroy]

  def destroy
    column_settings = this_column_settings
    destroyed = column_settings.delete_option(option_params[:id])

    unless destroyed
      return render_json_error(error: "Option not found in column settings", status: :unprocessable_entity)
    end

    if this_column.update(settings: column_settings.serialize)
      render(json: { memexProjectColumn: this_column.to_hash }, status: :accepted)
    else
      render_json_error(error: "Something went wrong", status: :unprocessable_entity)
    end
  end

  private

  def option_params
    underscored_params.require(:option).permit(:id, :name, :color, :description, :position)
  end

  def require_positive_position
    position = option_params[:position]

    if position && position.to_i < 1
      render_json_error(error: "Position must be a positive integer", status: :unprocessable_entity)
    end
  end

  def require_this_column
    render_404 unless this_column
  end

  def require_valid_data_type
    unless this_column.data_type == "single_select"
      render_json_error(
        error: "You may only update a single_select column's options",
        status: :unprocessable_entity,
      )
    end
  end

  def this_column # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @this_column ||= \
      this_memex.find_column_by_name_or_id(underscored_params[:memex_project_column_id])
  end

  def this_column_settings
    @this_column_settings = begin
      MemexProjectColumn::Settings.new(this_column.data_type, this_column.settings&.with_indifferent_access)
    rescue MemexProjectColumn::Settings::InitializationError
      nil
    end
  end
end
