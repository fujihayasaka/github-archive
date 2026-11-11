# typed: strict
# frozen_string_literal: true

class UserShortcutsController < ApplicationController
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency

  SHORTCUT_FIELDS = %i[name searchType query description icon color].freeze

  allow_verified_fetch only: %w(create update destroy)

  before_action :login_required
  before_action :ff_enabled
  before_action :try_parse_json_params, only: %i[create update]
  before_action :require_all_shortcut_fields, only: %i[create update]
  before_action :shortcut_exists, only: %i[update destroy]
  before_action :shortcut_belongs_to_user, only: %i[update destroy]
  before_action :restrict_search_type_update, only: %i[update]

  sig { void }
  def create
    ApplicationRecord::Collab.transaction do
      created_shortcut = SearchShortcut.create!(dashboard: user_dashboard, **shortcut_params_for_model)
      render json: { shortcut: shortcuts_payload(created_shortcut) }

    rescue ArgumentError, ActiveRecord::RecordInvalid => e
      render_error(e.message, :bad_request)
    end
  end

  sig { void }
  def update
    begin
      T.must(shortcut).update!(shortcut_params_for_model)
      render json: { shortcut: shortcuts_payload(T.must(shortcut)) }

    rescue ArgumentError, ActiveRecord::RecordInvalid => e
      render_error(e.message, :bad_request)
    end
  end

  sig { void }
  def destroy
    T.must(shortcut).destroy!
    head :ok
  end

  private

  sig { params(shortcut: SearchShortcut).returns(T::Hash[Symbol, T.untyped]) }
  def shortcuts_payload(shortcut)
    {
      id: shortcut.id,
      name: shortcut.name,
      description: shortcut.description,
      icon: shortcut.icon,
      color: shortcut.color,
      query: shortcut.compressed_query,
      searchType: shortcut.search_type,
    }
  end

  sig { void }
  def ff_enabled
    render_404 unless FeatureFlag.vexi.enabled?(:repos_finder_shortcuts, current_user, default: false)
  end

  sig { returns(T.nilable(SearchShortcut)) }
  memoize def shortcut
    SearchShortcut.find_by(id: params[:id])
  end

  sig { void }
  def shortcut_exists
    render_error("Shortcut not found", :not_found) unless shortcut.present?
  end

  sig { void }
  def shortcut_belongs_to_user
    render_error("Shortcut not found", :not_found) unless T.must(shortcut).dashboard&.user == current_user
  end

  sig { void }
  def require_all_shortcut_fields
    missing_fields = SHORTCUT_FIELDS.reject { |field| shortcut_params.key?(field) }
    render_error("Missing required fields: #{missing_fields.join(', ')}", :bad_request) if missing_fields.any?
  end

  sig { void }
  def restrict_search_type_update
    invalid_search_type = shortcut_params.include?(:searchType) && T.must(shortcut).search_type != shortcut_params[:searchType]

    render_error("Updating searchType is not allowed", :bad_request) if invalid_search_type
  end

  sig { params(message: String, status: Symbol).void }
  def render_error(message, status)
    render json: { error: { message: message } }, status: status
  end

  sig { returns(ActionController::Parameters) }
  memoize def shortcut_params
    params.expect(view: SHORTCUT_FIELDS)
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def shortcut_params_for_model
    values = shortcut_params.to_h
    values["search_type"] = values.delete("searchType")
    values
  end

  sig { returns(UserDashboard) }
  memoize def user_dashboard
    current_user.dashboard || UserDashboard.create!(user: current_user)
  end

  sig { returns(T.any(User, Symbol)) }
  def target_for_conditional_access
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    current_user
  end
end
