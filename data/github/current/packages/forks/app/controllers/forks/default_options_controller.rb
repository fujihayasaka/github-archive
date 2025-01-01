# typed: true
# frozen_string_literal: true

class Forks::DefaultOptionsController < ApplicationController
  include Forks::ForksControllerDependency

  before_action :validate_default_settings_enabled, only: [:update]

  # Saves a user's preferred search defaults
  def update
    new_settings = safe_options_resolver.to_options_args

    # Don't attempt the write unless the values are actually different.
    unless user_default_options == new_settings
      settings_record = T.cast(user_settings_record || UserSettings.create!(user_id: current_user.id), T.untyped)
      # Untyping the settings_record because the `set!` method is seemingly too magic for Sorbet
      settings_record.set!(:forks_view_default_options, safe_options_resolver.to_options_args.to_json)
    end

    respond_to do |format|
      format.json do
        render json: { success: true }, status: 200
      end
    end
  end

  private

  sig { returns(Repository) }
  memoize def current_repository
    return super unless params[:user_id] && params[:repository]
    owner = User.find_by_login(params[:user_id])
    T.must(owner.find_repo_by_name(params[:repository]))
  end

  def current_user
    super
  end

  def target_for_conditional_access
    logged_in? ? current_user : :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  def resource_for_conditional_access
    logged_in? ? current_user : :no_resource_for_conditional_access # rubocop:disable GitHub/SpecifyResourceForConditionalAccess

  end

  def permitted_params
    params.permit(:sort_by, :period, :user_id, :repository, :include)
  end

  def validate_default_settings_enabled
    render(json: { success: false }, status: 404) unless logged_in?
  end
end
