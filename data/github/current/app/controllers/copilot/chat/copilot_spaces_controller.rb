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
    ApplicationRecord::Iam,
    only: [:index, :show]

  def index
    editable_promises = copilot_spaces.map do |copilot|
      copilot.async_editable_by?(current_user)
    end
    adminable_promises = copilot_spaces.map do |copilot|
      copilot.async_adminable_by?(current_user)
    end

    editable_results = Promise.all(editable_promises).sync
    adminable_results = Promise.all(adminable_promises).sync

    json = copilot_spaces.map.with_index do |copilot, index|
      assign_user_and_cap(copilot)
      CopilotSpaces::PageData::CopilotSpace::IndexPayload.call(
        copilot,
        editable: editable_results[index],
        adminable: adminable_results[index]
      ).as_json
    end
    render json: to_camel_case_json(json)
  end

  def show
    started_at = Time.now
    copilot_space = if params[:owner].present? && params[:number].present?
      if FeatureFlag.vexi.enabled?(:copilot_spaces_read_access_to_user_owned_spaces, current_user, default: false)
        CopilotSpace.for_owner_login_and_number_with_user_roles!(params[:owner], params[:number])
      else
        CopilotSpace.for_owner_login_and_number!(params[:owner], params[:number])
      end
    else
      if FeatureFlag.vexi.enabled?(:copilot_spaces_read_access_to_user_owned_spaces, current_user, default: false)
        # We need user_roles to determine if the space is accessible because it has collaborators or is a public space
        CopilotSpace.includes(:user_roles).find_by!(id: params[:id])
      else
        CopilotSpace.find_by!(id: params[:id])
      end
    end

    return render_404 unless copilot_space.readable_by?(current_user)

    payload = {}
    protected_organizations = copilot_space.protected_organizations(cap_filter: cap_filter)
    if copilot_space.owner.organization? && cap_filter.unauthorized_resources([copilot_space.owner]).any?
      owner_display_login = copilot_space.owner.display_login
      protected_organizations |= [owner_display_login]
    end

    if protected_organizations.any?
      payload = {
        protectedOrganizations: protected_organizations,
      }
    else
      assign_user_and_cap(copilot_space)
      payload_as_json_start = Time.now
      data = CopilotSpaces::PageData::CopilotSpace::Payload.call(copilot_space)
      payload = data.as_json
      payload_as_json_elapsed_time_seconds = Time.now - payload_as_json_start

      CopilotSpaces::HydroEventsHelper.instrument_generic_event("show", current_user, copilot_space, data: {
        controller: self.class.name,
        elapsed_time: Time.now - started_at,
        payload_as_json_elapsed_time_seconds: payload_as_json_elapsed_time_seconds,
        size_percentage: data.sizePercentage,
      })
    end

    render json: payload
  end

  private

  memoize def copilot_spaces
    orgs = CopilotSpaces::AuthorizationHelper.authorized_orgs_with_copilot_access(current_user, cap_filter)
    orgs_ids = orgs.map(&:id)

    adminable_org_ids = orgs
      .select { |org| org.adminable_by?(current_user) }
      .map(&:id)
    org_adminable_private_copilots = CopilotSpace.where(owner: adminable_org_ids, visibility: :private)

    org_public_copilots = CopilotSpace.where(owner: orgs_ids, visibility: :org_public).or(
      CopilotSpace.where(owner: orgs_ids).where.not(base_role: :none)
    )
    spaces_assigned_role_ids = UserRole.where(target_type: "CustomCopilot", actor_type: "User", actor_id: current_user.id).pluck(:target_id)

    if FeatureFlag.vexi.enabled?(:copilot_spaces_read_access_to_user_owned_spaces, current_user, default: false)
      spaces_assigned_role = CopilotSpace.where(id: spaces_assigned_role_ids)
    else
      # Only include spaces that the current user owns or that are org-owned
      # (exclude spaces owned by other users) — this prevents showing user-owned
      # spaces from other users even if the current user has been assigned a role
      spaces_assigned_role_base = CopilotSpace.where(id: spaces_assigned_role_ids)
      spaces_assigned_role = spaces_assigned_role_base
        .where(owner: current_user)
        .or(spaces_assigned_role_base.where(owner: orgs))
    end

    if FeatureFlag.vexi.enabled?(:copilot_spaces_read_access_to_user_owned_spaces, current_user, default: false) && FeatureFlag.vexi.enabled?(:copilot_spaces_public_access_to_user_owned_spaces, current_user, default: false)
      starred_public_spaces = CopilotSpace.starred_by(current_user).public_spaces

      spaces_scope = org_public_copilots
        .or(spaces_assigned_role)
        .or(org_adminable_private_copilots)
        .or(starred_public_spaces)
    else
      spaces_scope = org_public_copilots
        .or(spaces_assigned_role)
        .or(org_adminable_private_copilots)
    end

    if FeatureFlag.vexi.enabled?(:copilot_spaces_read_access_to_user_owned_spaces, current_user, default: false)
      # We need user_roles to determine if the space is accessible because it has collaborators or is a public space
      spaces_scope.includes(:stars, { owner: :profile }, :resources, :user_roles)
        .reject { |copilot| copilot.protected_organizations(cap_filter: cap_filter).any? }
        .sort_by { |copilot| copilot.name.downcase }
    else
      spaces_scope.includes(:stars, { owner: :profile }, :resources)
        .reject { |copilot| copilot.protected_organizations(cap_filter: cap_filter).any? }
        .sort_by { |copilot| copilot.name.downcase }
    end
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
