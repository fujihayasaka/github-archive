# typed: strict
# frozen_string_literal: true

class Stafftools::CopilotQuotaEventsController < StafftoolsController
  layout "layouts/stafftools/user/content"

  before_action :dotcom_required
  before_action :ensure_feature_enabled
  before_action :ensure_user_exists
  before_action :ensure_user_not_org

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Copilot,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    only: [:show, :create]

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = T.let([
    "Stafftools::CopilotQuotaEventsController#create",
  ].freeze, T::Array[String])

  VALID_FEATURES = T.let(
    %w[chat completions].freeze,
    T::Array[String],
  )

  VALID_QUOTA_REQUEST_TYPES = T.let({
    "USER_INITIATED" => :USER_INITIATED,
    "SYSTEM_INITIATED" => :SYSTEM_INITIATED,
    "ORG_INITIATED" => :ORG_INITIATED,
  }.freeze, T::Hash[String, Symbol])

  sig { void }
  def show
    user = this_user
    copilot_user = Copilot::User.new(user)
    access_type = resolve_access_type(copilot_user)

    target_user_enabled = user.feature_flag_enabled?(
      :copilot_limiter_stafftools_broadcast_quota_events, default: false
    )

    render "stafftools/copilot_quota_events/show", locals: {
      user:,
      copilot_tracking_id: user.analytics_tracking_id,
      copilot_access_type: access_type,
      target_user_enabled:,
    }
  end

  sig { void }
  def create
    user = this_user

    unless user.feature_flag_enabled?(:copilot_limiter_stafftools_broadcast_quota_events, default: false)
      flash[:error] = "Target user is not enabled for quota event broadcasting. " \
        "Enable the copilot_limiter_stafftools_broadcast_quota_events flag for this user first."
      redirect_to stafftools_user_copilot_quota_events_path(user) and return
    end

    qe = quota_event_params
    feature = qe[:feature].to_s

    unless VALID_FEATURES.include?(feature)
      flash[:error] = "Feature is required and must be one of: #{VALID_FEATURES.join(", ")}"
      redirect_to stafftools_user_copilot_quota_events_path(user) and return
    end

    unless qe[:calculated_tbb_aiu_quantity].present?
      flash[:error] = "Calculated TBB AIU Quantity is required."
      redirect_to stafftools_user_copilot_quota_events_path(user) and return
    end

    copilot_user = Copilot::User.new(user)
    access_type = resolve_access_type(copilot_user)

    quota_request_type = VALID_QUOTA_REQUEST_TYPES.fetch(qe[:quota_request_type].to_s, :USER_INITIATED)

    message = {
      feature:,
      github_copilot_units: 0,
      copilot_tracking_id: user.analytics_tracking_id,
      github_user_id: user.id,
      copilot_access_type: access_type,
      quota_source: :DEVELOPMENT,
      stamp: GitHub::Config::Proxima.current_stamp_or_dotcom,
      model: "claude-opus-4",
      model_name: "claude-opus-4",
      model_multiplier: 1.0,
      is_premium: true,
      is_token_based_billing: true,
      quota_request_type:,
      integration_id: "playground-dev",
      interaction_type: "chat",
      initiator: :INITIATOR_USER,
      model_selection_method: :SELECTED_BY_USER,
      is_failed_request: false,
      repo_id: 0,
    }

    tbb_aiu = qe[:calculated_tbb_aiu_quantity].presence
    tbb_aiu_float = tbb_aiu.to_f
    if tbb_aiu_float <= 0
      flash[:error] = "Calculated TBB AIU Quantity must be a positive number."
      redirect_to stafftools_user_copilot_quota_events_path(user) and return
    end
    message[:calculated_tbb_aiu_quantity] = { value: tbb_aiu_float }
    message[:aiu_quantity_nano] = (tbb_aiu_float * 1_000_000_000).to_i

    begin
      Hydro::PublishRetrier.publish(
        message,
        schema: "copilot.v0.QuotaEvent",
        publisher: GitHub.hydro_copilot_publisher,
        partition_key: user.analytics_tracking_id,
      )
    rescue => e
      flash[:error] = "Failed to publish QuotaEvent: #{e.message}"
      redirect_to stafftools_user_copilot_quota_events_path(user) and return
    end

    instrument("staff.copilot_quota_event_broadcast", {
      staff_actor: current_user.login,
      target_user: user.login,
      feature:,
    })

    flash[:notice] = "QuotaEvent published for #{user.display_login} (feature: #{feature})." \
      "The Copilot Limiter will process this event shortly."
    redirect_to stafftools_user_copilot_quota_events_path(user)
  end

  private

  sig { params(copilot_user: Copilot::User).returns(Symbol) }
  def resolve_access_type(copilot_user)
    access_type = copilot_user.access_type
    valid_types = Hydro::Schemas::Github::Copilot::V0::Entities::CopilotAccessType
      .descriptor.to_h.keys.map(&:to_sym).to_set
    if valid_types.include?(access_type)
      access_type
    else
      :UNKNOWN
    end
  end

  sig { void }
  def ensure_feature_enabled
    unless current_user&.feature_flag_enabled?(:copilot_limiter_stafftools_broadcast_quota_events, default: false)
      render_404
    end
  end

  sig { void }
  def ensure_user_not_org
    if this_user&.organization?
      flash[:error] = "QuotaEvent broadcasting is only supported for individual users, not organizations."
      redirect_to stafftools_user_copilot_settings_path(this_user)
    end
  end

  sig { returns(ActionController::Parameters) }
  def quota_event_params
    params.require(:quota_event).permit(:feature, :calculated_tbb_aiu_quantity, :quota_request_type)
  end
end
