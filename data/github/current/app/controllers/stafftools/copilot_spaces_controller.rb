# rubocop:disable GitHub/UseRestfulActions
# typed: true
# frozen_string_literal: true

class Stafftools::CopilotSpacesController < StafftoolsController
  before_action :dotcom_required
  before_action :require_user
  before_action :find_space, except: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Copilot,
    ApplicationRecord::Collab,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    only: [:index, :show, :update, :destroy, :add_collaborator, :update_collaborator, :remove_collaborator]

  helper_method :render_resource_title, :render_resource_details, :resource_viewable?, :resource_url

  # List all spaces for a user (was in copilot_spaces_controller#show)
  def index
    spaces = CopilotSpace.where(owner: @user).includes(:resources, :creator, :user_roles).order(:name)
    spaces_array = spaces.to_a

    total_spaces = spaces_array.count
    total_resources = spaces_array.sum { |space| space.resources.count }
    total_public_spaces = spaces_array.count { |space| space.base_role != "none" }
    total_private_spaces = spaces_array.count { |space| space.base_role == "none" && !space.has_collaborators? }
    total_shared_private_spaces = spaces_array.count { |space| space.base_role == "none" && space.has_collaborators? }

    if @user.organization?
      render "stafftools/copilot_spaces/org_show", locals: {
        spaces: spaces_array,
        total_spaces: total_spaces,
        total_resources: total_resources,
        total_public_spaces: total_public_spaces,
        total_private_spaces: total_private_spaces,
        total_shared_private_spaces: total_shared_private_spaces,
        org: @user,
      }, layout: "layouts/stafftools/organization/content"
    else
      render "stafftools/copilot_spaces/show", locals: {
        spaces: spaces_array,
        total_spaces: total_spaces,
        total_resources: total_resources,
        total_public_spaces: total_public_spaces,
        total_private_spaces: total_private_spaces,
        total_shared_private_spaces: total_shared_private_spaces,
        user: @user,
      }, layout: "layouts/stafftools/user/content"
    end
  end

  # Show individual space details
  def show
    @space.current_user = current_user
    @collaborators = @space.user_roles

    render "stafftools/copilot_space/show", locals: {
      space: @space,
      collaborators: @collaborators,
      user: @user,
      is_org_context: @space.owner.organization?
    }, layout: layout_for_user
  end

  # Update space (only base_role for now)
  def update
    if params[:copilot_space] && params[:copilot_space][:base_role]
      old_base_role = @space.base_role
      new_base_role = params[:copilot_space][:base_role]

      if @space.update(base_role: new_base_role)
        flash[:notice] = "Copilot Space '#{@space.name}' visibility updated from '#{old_base_role.humanize}' to '#{new_base_role.humanize}'."
      else
        flash[:error] = "Failed to update Copilot Space visibility: #{@space.errors.full_messages.join(', ')}"
      end
    end

    redirect_to stafftools_space_path
  end

  # Add collaborator to space
  def add_collaborator
    collaborator = @space.add_collaborator!(
      user_login: params[:user_login],
      role_name: params[:role_name]
    )
    flash[:notice] = "Added '#{actor_display_name(collaborator)}' as #{params[:role_name].humanize} to the space"
    redirect_to stafftools_space_path
  rescue CopilotSpace::PermissionsDependency::CollaboratorError => e
    flash[:error] = e.message
    redirect_to stafftools_space_path
  end

  # Update collaborator role
  def update_collaborator
    user_role_id = params[:user_role_id]
    new_role_name = params[:role_name]

    @space.update_user_role_by_name!(role_name: new_role_name, user_role_id: user_role_id.to_i)

    # Find the user role to get the actor for the flash message
    user_role = @space.user_roles.find { |ur| ur.id == user_role_id.to_i }
    flash[:notice] = "Updated #{actor_display_name(user_role.actor)}'s role to #{new_role_name.humanize}"
    redirect_to stafftools_space_path
  rescue CopilotSpace::PermissionsDependency::CollaboratorError => e
    flash[:error] = e.message
    redirect_to stafftools_space_path
  end

  # Remove collaborator
  def remove_collaborator
    collaborator = @space.remove_collaborator!(user_role_id: params[:user_role_id].to_i)
    flash[:notice] = "Removed '#{actor_display_name(collaborator)}' from the space"
    redirect_to stafftools_space_path
  rescue CopilotSpace::PermissionsDependency::CollaboratorError => e
    flash[:error] = e.message
    redirect_to stafftools_space_path
  end

  # Handles resource deletion
  def destroy_resource
    @resource = @space.resources.find(params[:resource_id])

    if @resource.destroy
      flash[:notice] = "Resource '#{resource_title(@resource)}' has been removed from the space."
    else
      flash[:error] = "Failed to remove resource: #{@resource.errors.full_messages.join(', ')}"
    end

    redirect_to stafftools_space_path
  end

  def destroy
    space_name = @space.name
    space_owner = @space.owner

    if @space.destroy
      flash[:notice] = "Copilot Space '#{space_name}' has been deleted successfully."
    else
      flash[:error] = "Failed to delete Copilot Space: #{@space.errors.full_messages.join(', ')}"
    end

    redirect_to Rails.application.routes.url_helpers.stafftools_user_copilot_spaces_path(space_owner)
  end

  private

  def render_resource_title(resource)
    CopilotSpaces::StafftoolsHelper.resource_title(resource)
  end

  def render_resource_details(resource)
    CopilotSpaces::StafftoolsHelper.resource_details(resource)
  end

  def resource_title(resource)
    CopilotSpaces::StafftoolsHelper.resource_title(resource)
  end

  def resource_details(resource)
    CopilotSpaces::StafftoolsHelper.resource_details(resource)
  end

  def resource_viewable?(resource)
    CopilotSpaces::StafftoolsHelper.resource_viewable?(resource)
  end

  def resource_url(resource)
    CopilotSpaces::StafftoolsHelper.resource_url(resource, request.base_url)
  end

  def find_space
    return render_404 unless @user

    @space = CopilotSpace.includes(user_roles: [:role, :actor]).find_by(id: params[:id], owner: @user)
    return render_404 unless @space

    T.must(@space).current_user = current_user
  end

  def require_user
    unless this_user
      render_404
      return
    end

    @user = this_user
  end

  def layout_for_user
    if @user.organization?
      "layouts/stafftools/organization/content"
    else
      "layouts/stafftools/user/content"
    end
  end

  def stafftools_space_path
    Rails.application.routes.url_helpers.stafftools_user_copilot_space_path(@user, @space)
  end

  # Helper method to get display name for actors (User or Team)
  def actor_display_name(actor)
    case actor
    when User
      actor.display_login
    when Team
      actor.combined_slug
    else
      actor.to_s
    end
  end
end

# rubocop:enable GitHub/UseRestfulActions
