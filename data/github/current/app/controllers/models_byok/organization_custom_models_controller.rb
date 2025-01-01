# typed: true
# frozen_string_literal: true

class ModelsByok::OrganizationCustomModelsController < Orgs::Controller
  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency

  before_action :organization_admin_required
  before_action :github_models_required
  before_action :parse_json_params, only: [:create, :update]

  # Allow making requests to this endpoint from React apps using the `verifiedFetch` function:
  allow_verified_fetch only: [:create, :update]

  depends_on_clusters ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::GitHubModels,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql1,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    only: [:index],
    optional: true

  layout "organization_settings"

  def self.react_bundle_name
    "models-byok-settings"
  end

  def index
    respond_with_react(
      payload: CustomModelsIndexPayload.new(org:),
      title: "#{this_organization.display_login} settings · Custom models",
      page_data: {
        selected_link: :github_models_organization_custom_models,
      },
    )
  end

  def create
    result = ModelsByok::CreateCustomKey.call(
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
    head(success ? :ok : :unprocessable_entity)
  end

  class CustomModelsIndexPayload < ReactPayload::Base
    def route_id
      "customModelsIndexRoute"
    end

    sig { params(org: ::Organization).void }
    def initialize(org:)
      @org = org
    end

    def payload
      enabled = @org.custom_models_enabled?
      custom_keys = @org.models_custom_keys.newest_first
      custom_models = @org.custom_models.sort do |a, b|
        ::ModelsByok::CustomModel.key_and_name_sort(a, b)
      end

      {
        publicKey: ModelsByok::CustomKey.encryption_public_key(@org),
        orgDisplayLogin: @org.display_login,
        customKeys: enabled ? custom_keys.map(&:to_h) : [],
        customModels: enabled ? custom_models.map(&:to_h) : [],
        enabled: enabled,
      }
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

  sig { returns ModelsByok::CustomModel }
  memoize def custom_model
    org.custom_models.find(params[:id])
  end
end
