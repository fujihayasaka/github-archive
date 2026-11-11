# typed: true
# frozen_string_literal: true

class Orgs::CopilotSettings::ByokCustomModelsController < Orgs::Controller
  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::FeatureFlagsDependency

  before_action :organization_admin_required
  before_action :copilot_required
  before_action :parse_json_params, only: [:create, :update]

  # Allow making requests to this endpoint from React apps using the `verifiedFetch` function:
  allow_verified_fetch only: [:index, :create, :update]

  depends_on_clusters ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Copilot,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    only: [:index],
    optional: true

  javascript_bundle :settings

  sig { returns(String) }
  def self.react_bundle_name
    "copilot-byok-settings"
  end

  def index
    respond_with_react(
      payload: CustomModelsIndexPayload.new(org:),
      title: "#{this_organization.display_login} settings · Custom models",
      layout: "layouts/settings/copilot_org_react",
      page_data: {
        selected_link: :organization_copilot_settings_models,
      },
    )
  end

  def create
    result = CopilotByok::CreateCustomKey.call(
      owner: org,
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
    return render(json: custom_model.to_h) if success
    render json: { message: custom_model.errors.full_messages.to_sentence }, status: :unprocessable_entity
  end

  class CustomModelsIndexPayload < ReactPayload::Base
    include GitHub::Memoizer

    sig { params(org: ::Organization).void }
    def initialize(org:)
      @org = org
      @business = org.business
    end

    # As defined in packages/models-byok-settings/routes/CustomModelsIndex/custom-models-index-route.ts from github/github-ui
    def route_id
      "customModelsIndexRoute"
    end

    def payload
      # Keep in sync with `CustomModelsIndexPayload` in packages/copilot-byok-settings/types.ts in github/github-ui
      {
        publicKey: CopilotByok::CustomKey.encryption_public_key(@org),
        orgDisplayLogin: @org.display_login,
        enterprise: enterprise,
        customKeys: custom_keys_for_payload,
        customModels: custom_models_for_payload,
        enabled: enabled?,
        availableProviders: CopilotByok::CustomKey.available_providers_for(@org)
      }
    end

    private

    sig { returns T::Boolean }
    memoize def enabled?
      @org.copilot_custom_models_enabled?
    end

    sig { returns T::Array[CopilotByok::Types::CustomKey] }
    def custom_keys_for_payload
      return [] unless enabled?

      enterprise_model_counts = self.enterprise_model_counts_by_custom_key_id
      all_custom_keys.map do |custom_key|
        custom_key.to_h(
          # All the org's custom models will be shown on the page, so let #to_h count them all. For an enterprise
          # custom model, though, only those allowed for the org will be shown, so only count those:
          total_models: custom_key.enterprise_owned? ? enterprise_model_counts[custom_key.id] : nil,

          # Enterprise-owned custom keys are never editable from organization settings:
          editable: custom_key.organization_owned?,
        )
      end
    end

    sig { returns T::Array[CopilotByok::Types::CustomModel] }
    def custom_models_for_payload
      return [] unless enabled?

      all_custom_models.map do |custom_model|
        # TODO: also include check of enterprise policy, once such a thing exists, if the org belongs to an
        # enterprise, to see whether the enterprise allows its organizations to set their own policy regarding
        # inherited custom models; for now only org-owned models are editable in org settings
        is_editable = custom_model.organization_owned?

        custom_model.to_h(editable: is_editable)
      end
    end

    sig { returns T::Array[CopilotByok::CustomModel] }
    memoize def enterprise_custom_models
      return [] unless @business.present?
      policy = CopilotByok::CustomModelPolicy.new(business: @business)
      policy.enabled_models_for(@org)
    end

    sig { returns T::Array[CopilotByok::CustomModel] }
    def org_custom_models
      org_custom_keys.flat_map(&:custom_models)
    end

    sig { returns T::Array[CopilotByok::CustomModel] }
    memoize def all_custom_models
      (enterprise_custom_models + org_custom_models).sort do |a, b|
        ::CopilotByok::CustomModel.key_and_name_sort(a, b)
      end
    end

    sig { returns T::Hash[Integer, Integer] }
    def enterprise_model_counts_by_custom_key_id
      enterprise_custom_models.each_with_object(Hash.new(0)) do |custom_model, hash|
        hash[custom_model.custom_key_id] += 1
      end
    end

    sig { returns T::Array[CopilotByok::CustomKey] }
    memoize def org_custom_keys
      @org.copilot_custom_keys.newest_first.includes(custom_models: :capability).to_a
    end

    sig { returns T::Array[CopilotByok::CustomKey] }
    def enterprise_custom_keys
      enterprise_custom_models.map(&:custom_key).compact.uniq.sort_by(&:created_at).reverse
    end

    sig { returns T::Array[CopilotByok::CustomKey] }
    def all_custom_keys
      enterprise_custom_keys + org_custom_keys
    end

    sig { returns T.nilable(Hash) }
    def enterprise
      return nil unless @business
      { name: @business.name, slug: @business.slug }
    end
  end

  private

  sig { returns ActionController::Parameters }
  memoize def update_params
    result = params.permit(:organization_id, :id, :name, :copilot_chat_enabled,
      capability_attributes: %i(max_input_tokens max_output_tokens tool_calling vision thinking streaming max_context_window endpoint_type))
    if result[:capability_attributes]
      result[:capability_attributes][:id] = custom_model.capability&.id
      result[:capability_attributes].delete(:max_input_tokens) if result[:capability_attributes][:max_input_tokens].nil?
      result[:capability_attributes].delete(:max_output_tokens) if result[:capability_attributes][:max_output_tokens].nil?
      result[:capability_attributes].delete(:max_context_window) if result[:capability_attributes][:max_context_window].nil?
    end
    result
  end

  sig { returns(::Organization) }
  memoize def org
    T.cast(this_organization, ::Organization)
  end

  sig { returns CopilotByok::CustomModel }
  memoize def custom_model
    org.copilot_custom_models.find(params[:id])
  end
end
