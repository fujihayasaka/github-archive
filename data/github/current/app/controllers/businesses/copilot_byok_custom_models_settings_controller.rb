# typed: true
# frozen_string_literal: true

class Businesses::CopilotByokCustomModelsSettingsController < Businesses::BusinessController
  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency

  before_action :dotcom_required
  before_action :business_owner_required
  before_action :business_not_downgraded_to_free_plan_required
  before_action :ensure_copilot_enabled
  before_action :parse_json_params, only: [:create, :update]

  depends_on_clusters ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Copilot,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql1,
    only: [:index]

  depends_on_clusters ApplicationRecord::Billing,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    only: [:index],
    optional: true

  # Allow making requests to this endpoint from React apps using the `verifiedFetch` function:
  allow_verified_fetch only: [:index, :create, :update]

  sig { returns(String) }
  def self.react_bundle_name
    "copilot-byok-enterprise-settings"
  end

  sig { void }
  def index
    show_ai_controls = helpers.show_ai_controls?(this_business)
    payload = CustomModelsIndexPayload.new(
      business: this_business,
      show_ai_controls: show_ai_controls,
      custom_model_policy: custom_model_policy,
      enabled_features: client_feature_flags,
    ).payload
    if request.xhr?
      render json: payload
    else
      render "businesses/copilot_byok_custom_models_settings/index",
        locals: { payload: payload, show_ai_controls: show_ai_controls }
    end
  end

  def create
    result = CopilotByok::CreateCustomKey.call(
      owner: this_business,
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
    errors = update_custom_model_enablement
    unless custom_model.update(custom_model_update_params)
      errors += custom_model.errors.full_messages
    end
    if errors.empty?
      render json: custom_model.to_h
    else
      render json: { message: errors.join(", ") }, status: :unprocessable_entity
    end
  end

  class CustomModelsIndexPayload
    include GitHub::Memoizer

    sig do
      params(
        business: ::Business,
        show_ai_controls: T::Boolean,
        custom_model_policy: CopilotByok::CustomModelPolicy,
        enabled_features: T.nilable(T::Hash[T.any(String, Symbol), T::Boolean])
      ).void
    end
    def initialize(business:, show_ai_controls:, custom_model_policy:, enabled_features: nil)
      @business = business
      @show_ai_controls = show_ai_controls
      @custom_model_policy = custom_model_policy
      @enabled_features = enabled_features
    end

    def payload
      # Keep these props in sync with `CustomModelsIndexPayload` in
      # packages/copilot-byok-enterprise-settings/types.ts in github/github-ui
      {
        publicKey: CopilotByok::CustomKey.encryption_public_key(@business),
        enterpriseSlug: @business.slug,
        customKeys: custom_keys_for_payload,
        customModels: custom_models_for_payload,
        showAiControls: @show_ai_controls,
        tab: "custom-models",
        availableProviders: CopilotByok::CustomKey.available_providers_for(@business),
        customModelPolicy: @custom_model_policy.to_h,
        enabledFeatures: @enabled_features,
      }
    end

    private

    sig { returns T::Array[CopilotByok::Types::CustomKey] }
    def custom_keys_for_payload
      custom_keys = @custom_model_policy.custom_keys
      total_models_by_key_id = custom_models.each_with_object(Hash.new(0)) do |model, hash|
        hash[model.custom_key_id] += 1
      end
      custom_keys.map { |key| key.to_h(total_models: total_models_by_key_id[key.id], editable: true) }
    end

    sig { returns T::Array[CopilotByok::Types::CustomModel] }
    def custom_models_for_payload
      custom_models.sort { |a, b| ::CopilotByok::CustomModel.key_and_name_sort(a, b) }.map(&:to_h)
    end

    sig { returns T::Array[CopilotByok::CustomModel] }
    memoize def custom_models
      result = @custom_model_policy.custom_models
      GitHub::PrefillAssociations.prefill_associations(result, :capability)
      result
    end
  end

  private

  sig { returns(Copilot::Business) }
  memoize def copilot_business
    Copilot::Business.new(this_business)
  end

  sig { returns CopilotByok::CustomModel }
  memoize def custom_model
    this_business.copilot_custom_models.find(params[:id])
  end

  sig { returns ActionController::Parameters }
  memoize def permitted_params
    params.permit(
      :slug, # used in the URL
      :all_orgs_access_setting, # used to allow/disallow model for all the enterprise's orgs

      # Used to update the `copilot_custom_models` record:
      :id, :name, :copilot_chat_enabled, capability_attributes: %i(max_input_tokens max_output_tokens tool_calling
        vision thinking streaming max_context_window endpoint_type),

      allowed_org_ids: [], # used to allow access to the model for specific orgs
    )
  end

  sig { returns ActionController::Parameters }
  memoize def custom_model_update_params
    result = permitted_params.slice(:name, :copilot_chat_enabled, :capability_attributes)
    if result[:capability_attributes]
      result[:capability_attributes][:id] = custom_model.capability&.id
      if result[:capability_attributes][:max_input_tokens].nil?
        result[:capability_attributes].delete(:max_input_tokens)
      end
      if result[:capability_attributes][:max_output_tokens].nil?
        result[:capability_attributes].delete(:max_output_tokens)
      end
      if result[:capability_attributes][:max_context_window].nil?
        result[:capability_attributes].delete(:max_context_window)
      end
    end
    result
  end

  sig { returns T::Array[String] }
  def update_custom_model_enablement
    should_modify_access = permitted_params[:allowed_org_ids].present? ||
      permitted_params[:all_orgs_access_setting].present?
    return [] unless should_modify_access

    errors = T.let([], T::Array[String])

    if permitted_params[:allowed_org_ids].present?
      org_ids_to_allow = permitted_params[:allowed_org_ids].compact.map(&:to_i)
      org_ids_to_disallow = custom_model_policy.allowed_org_ids_for(custom_model) - org_ids_to_allow
      clear_global_rule_result = custom_model_policy.clear_all_org_rule_for(custom_model)
      errors += clear_global_rule_result.errors
      if org_ids_to_disallow.any?
        disallow_result = custom_model_policy.disable_custom_model_for_orgs(custom_model,
          org_ids: org_ids_to_disallow)
        errors += disallow_result.errors
      end
      if org_ids_to_allow.present?
        allow_result = custom_model_policy.enable_custom_model_for_orgs(custom_model, org_ids: org_ids_to_allow)
        errors += allow_result.errors
      end
    elsif permitted_params[:all_orgs_access_setting].to_s == "1"
      result = custom_model_policy.enable_custom_model_for_all_orgs(custom_model)
      errors += result.errors
    end

    errors
  end

  sig { void }
  def ensure_copilot_enabled
    render_404 unless copilot_business.copilot_enabled?
  end

  sig { returns CopilotByok::CustomModelPolicy }
  memoize def custom_model_policy
    CopilotByok::CustomModelPolicy.new(business: this_business)
  end
end
