# typed: true
# frozen_string_literal: true

class Copilot::Chat::CustomCopilotsController < Copilot::Chat::AbstractChatController
  allow_verified_fetch only: [:index, :destroy]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Copilot,
    ApplicationRecord::IamAbilities,
    only: [:index, :destroy, :show]

  def index
    return head :not_found unless feature_enabled_globally_or_for_current_user?(:copilot_custom_copilots)

    json = custom_copilots.map do |copilot|
      copilot.as_json(
        only: [:id, :name, :slug, :updated_at, :description, :general_instructions],
        methods: [:slug_with_owner, :primary_avatar_path],
        root: false
      ).merge(
        protectedOrganizations: copilot.protected_organizations(cap_filter: cap_filter, custom_copilot: copilot)
      )
    end
    render json: to_camel_case_json(json)
  end

  def show
    return head :not_found unless feature_enabled_globally_or_for_current_user?(:copilot_custom_copilots)

    custom_copilot = CustomCopilot.find_by(id: params[:id], owner: current_user)
    return head :not_found if custom_copilot.nil?

    payload = {
      id: custom_copilot.id,
      name: custom_copilot.name,
      description: custom_copilot.description,
      generalInstructions: custom_copilot.general_instructions,
      protectedOrganizations: custom_copilot.protected_organizations(cap_filter: cap_filter, custom_copilot:),
      resources: custom_copilot.resources_react_payload(viewer: current_user, cap_filter:),
    }

    render json: payload
  end

  def destroy
    custom_copilot = custom_copilots.find_by(id: params[:id])
    return head :not_found unless custom_copilot

    custom_copilot.destroy!
    head :ok
  end

  private

  def custom_copilots
    CustomCopilot.where(owner: current_user)
  end

  sig { params(array: T::Array[Hash]).returns(T::Array[Hash]) }
  def to_camel_case_json(array)
    array.map { |item| item.transform_keys { |key| key.to_s.camelize(:lower) } }
  end

  # CAP is not bypassed here as AbstractChatController requires a logged in user
  def target_for_conditional_access
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    current_user
  end
end
