# typed: true
# frozen_string_literal: true

class Copilot::Chat::CopilotSpacesController < Copilot::Chat::AbstractChatController
  allow_verified_fetch only: [:index]
  before_action :require_copilot_spaces_feature_enabled

  rescue_from ActiveRecord::RecordNotFound, with: :render_404

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Copilot,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    only: [:index, :show]

  def index
    json = copilot_spaces.map do |copilot|
      assign_user_and_cap(copilot)
      CopilotSpaces::PageData::CopilotSpace::IndexPayload.call(copilot).as_json
    end
    render json: to_camel_case_json(json)
  end

  def show
    copilot_space = if params[:owner].present? && params[:number].present?
      CopilotSpace.for_owner_login_and_number!(params[:owner], params[:number])
    else
      CopilotSpace.find_by!(id: params[:id])
    end

    return render_404 unless copilot_space.readable_by?(current_user)

    payload = {}
    protected_organizations = copilot_space.protected_organizations(cap_filter: cap_filter)
    if user_feature_enabled?(:copilot_custom_copilots_org_owned) && copilot_space.owner.organization? && cap_filter.unauthorized_resources([copilot_space.owner]).any?
      protected_organizations << copilot_space.owner.display_login
    end

    if protected_organizations.any?
      payload = {
        protectedOrganizations: protected_organizations,
      }
    else
      assign_user_and_cap(copilot_space)
      payload = CopilotSpaces::PageData::CopilotSpace::Payload.call(copilot_space).as_json
    end

    render json: payload
  end

  private

  def copilot_spaces
    copilot_spaces = CopilotSpace.where(owner: current_user)

    if user_feature_enabled?(:copilot_custom_copilots_org_owned)
      orgs = CopilotSpaces::AuthorizationHelper.authorized_orgs_with_copilot_access(current_user, cap_filter)
      orgs_ids = orgs.map(&:id)

      org_public_copilots = CopilotSpace.where(owner: orgs_ids, visibility: :org_public)

      org_private_user_created_copilots = CopilotSpace.where(owner: orgs_ids, visibility: :private, creator: current_user)
      adminable_org_ids = orgs
        .select { |org| org.adminable_by?(current_user) }
        .map(&:id)

      org_adminable_private_copilots = CopilotSpace.where(owner: adminable_org_ids, visibility: :private)

      copilot_spaces = copilot_spaces
        .or(org_public_copilots)
        .or(org_private_user_created_copilots)
        .or(org_adminable_private_copilots)
    end

    copilot_spaces.includes(:stars, { owner: :profile }, :resources)
      .reject { |copilot| copilot.protected_organizations(cap_filter: cap_filter).any? }
      .sort_by { |copilot| copilot.name.downcase }
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

  def assign_user_and_cap(copilot_space)
    copilot_space.current_user = current_user
    copilot_space.cap_filter = cap_filter
  end
end
