# typed: true
# frozen_string_literal: true

class Orgs::CopilotSettings::ByokCustomModelsController < Orgs::Controller
  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::FeatureFlagsDependency

  before_action :organization_admin_required
  before_action :copilot_required
  before_action :require_feature
  before_action :parse_json_params, only: [:create, :update]
  before_action :require_xhr, only: :index

  # Allow making requests to this endpoint from React apps using the `verifiedFetch` function:
  allow_verified_fetch only: [:index, :create, :update]

  depends_on_clusters ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Copilot,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql1,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    only: [:index],
    optional: true

  def index
    render json: CustomModelsIndexPayload.new(org: org).payload
  end

  def create
    result = CopilotByok::CreateCustomKey.call(
      org: org,
      actor: current_user,
      provider: params[:provider],
      name: params[:name],
      api_key: params[:api_key],
      models: params[:models],
      deployment_url: params[:deployment_url],
    )

    custom_key = result.custom_key
    if custom_key
      render json: { name: custom_key.name }
    else
      render json: { message: result.error }, status: :unprocessable_entity
    end
  end

  def update
    custom_model.actor = current_user
    success = custom_model.update(update_params.except(:id, :organization_id))
    return head(:ok) if success
    render json: { message: custom_model.errors.full_messages.to_sentence }, status: :unprocessable_entity
  end

  class CustomModelsIndexPayload
    sig { params(org: ::Organization).void }
    def initialize(org:)
      @org = org
    end

    def payload
      enabled = @org.copilot_custom_models_enabled?

      # Keep in sync with `CustomModelsIndexPayload` in packages/copilot-byok-settings/types.ts in github/github-ui
      {
        publicKey: CopilotByok::CustomKey.encryption_public_key(@org),
        orgDisplayLogin: @org.display_login,
        customKeys: enabled ? custom_keys : [],
        customModels: enabled ? custom_models : [],
        enabled: enabled,
      }
    end

    private

    sig { returns T::Array[CopilotByok::Types::CustomKey] }
    def custom_keys
      @org.copilot_custom_keys.newest_first.map(&:to_h)
    end

    sig { returns T::Array[CopilotByok::Types::CustomModel] }
    def custom_models
      @org.copilot_custom_models.sort { |a, b| ::CopilotByok::CustomModel.key_and_name_sort(a, b) }.map(&:to_h)
    end
  end

  private

  sig { returns ActionController::Parameters }
  memoize def update_params
    params.permit(:organization_id, :id, :copilot_chat_enabled)
  end

  sig { returns(::Organization) }
  memoize def org
    T.cast(this_organization, ::Organization)
  end

  sig { returns CopilotByok::CustomModel }
  memoize def custom_model
    org.copilot_custom_models.find(params[:id])
  end

  def require_feature
    render_404 unless org.feature_flag_enabled?(:copilot_byok, default: false)
  end
end
