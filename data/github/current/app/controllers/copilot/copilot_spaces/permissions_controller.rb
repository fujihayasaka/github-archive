# typed: true
# frozen_string_literal: true

class Copilot::CopilotSpaces::PermissionsController < ApplicationController
  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency
  include CopilotSpaces::HydroEventsHelper
  include CopilotSpaces::FeaturePreviewRedirect

  before_action :require_copilot_spaces_feature_enabled
  before_action :login_required
  before_action :try_parse_json_params, only: [:create, :update, :destroy]
  before_action :require_space_admin_access
  before_action :require_xhr

  allow_verified_fetch only: [:create, :update, :destroy]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Iam,
    ApplicationRecord::Copilot, only: [:index]

  rescue_from ActiveRecord::RecordNotFound, with: :render_404

  def index
    user_roles = UserRole.where(target_type: "CustomCopilot", target_id: copilot_space.id).includes(:role, :actor)
    payload = user_roles.map do |user_role|
      actor = T.must(user_role.actor)
      CopilotSpaces::PageData::CopilotSpaceUserRole::Payload.call(role: T.must(user_role.role), actor: actor, copilot_space: copilot_space, current_user:)
    end.sort_by do |item|
      identifier = item.actor_type == "team" ? item.slug : item.display_login
      identifier&.downcase || ""
    end

    render json: payload, status: :ok
  end

  def create
    Permissions::Granters::RoleGranter.new(actor: assignee, target: copilot_space, role: requested_role).grant!
    render json: CopilotSpaces::PageData::CopilotSpaceUserRole::Payload.call(role: requested_role, actor: assignee, copilot_space:, current_user:), status: :ok
  end

  def update
    Permissions::Granters::RoleGranter.new(actor: assignee, target: copilot_space).revoke_if_exists!
    Permissions::Granters::RoleGranter.new(actor: assignee, target: copilot_space, role: requested_role).grant_unless_exists!

    render json: CopilotSpaces::PageData::CopilotSpaceUserRole::Payload.call(role: requested_role, actor: assignee, copilot_space: copilot_space, current_user:), status: :ok
  end

  def destroy
    Permissions::Granters::RoleGranter.new(actor: assignee, target: copilot_space).revoke_if_exists!
    head :ok
  end

  private

  def assignee
    if permission_params[:actor_type] == "user"
      User.find_by!(id: permission_params[:actor_id])
    elsif permission_params[:actor_type] == "team"
      Team.find_by!(id: permission_params[:actor_id])
    else
      raise "Unsupported actor type: #{permission_params[:actor_type]}"
    end
  end

  sig { returns(Role) }
  memoize def requested_role
    case permission_params[:role_name]
    when "custom_copilot_reader"
      Role.custom_copilot_reader_role
    when "custom_copilot_writer"
      Role.custom_copilot_writer_role
    when "custom_copilot_admin"
      Role.custom_copilot_admin_role
    else
      raise "Unsupported Copilot Space role type: #{permission_params[:role_name]}"
    end
  end

  sig { returns(CopilotSpace) }
  memoize def copilot_space
    CopilotSpace.for_owner_login_and_number!(params[:owner], params[:number])
  end

  def require_space_admin_access
    render_404 unless copilot_space.adminable_by?(current_user)
  end

  def resource_for_conditional_access
    return :no_resource_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
    current_user
  end

  def target_for_conditional_access
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    current_user
  end

  def permission_params
    params.expect(permission: [:actor_id, :role_name, :actor_type])
  end
end
