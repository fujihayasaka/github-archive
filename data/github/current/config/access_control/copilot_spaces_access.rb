# typed: true
# frozen_string_literal: true

class Api::AccessControl < Egress::AccessControl
  # The resource is the organization owning copilot spaces
  # Organization members can list copilot spaces that the org owns
  define_access :list_organization_copilot_spaces do |access|
    access.ensure_context :resource
    access.allow(:org_copilot_space_lister) { |context| context[:resource].try(:organization?) }
  end

  # The resource is the organization owning copilot space
  # If the owner is an organization, any user who is a member of the org
  # can view a copilot space the org owns
  define_access :get_organization_copilot_space do |access|
    access.ensure_context :resource
    access.allow(:org_copilot_space_viewer) { |context| context[:resource].owner.try(:organization?) }
  end

  # The resource is the organization where copilot space will be created
  # Only organization members with appropriate permissions can create spaces
  define_access :create_organization_copilot_space do |access|
    access.ensure_context :resource
    access.allow(:org_copilot_space_creator) { |context| context[:resource].try(:organization?) }
  end

  # The resource is a copilot space owned by organization
  # Organization members with appropriate permissions can update org spaces
  define_access :update_organization_copilot_space do |access|
    access.ensure_context :resource
    access.allow(:org_copilot_space_editor) { |context| context[:resource].owner.try(:organization?) }
  end

  # The resource is the user owning copilot spaces
  # Users can list their own spaces, and public user spaces are accessible to authenticated users
  # The access to each individual space in list is checked in the controller
  define_access :list_user_copilot_spaces do |access|
    access.ensure_context :resource
    access.allow(:user_copilot_space_lister) { |context| context[:resource].try(:user?) }
  end

  # The resource is a copilot space owned by user
  # Users can view their own spaces, and public user spaces are accessible to authenticated users
  # The access is checked in the user_copilot_space_viewer role
  define_access :get_user_copilot_space do |access|
    access.ensure_context :resource
    access.allow(:user_copilot_space_viewer) { |context| context[:resource].owner.try(:user?) }
  end

  # The resource is the user where copilot space will be created
  # Only the user themselves can create spaces for their account
  define_access :create_user_copilot_space do |access|
    access.ensure_context :resource
    access.allow(:user_copilot_space_creator) { |context| context[:resource].try(:user?) }
  end

  # The resource is a copilot space owned by user
  # Only the user themselves can update their own spaces
  define_access :update_user_copilot_space do |access|
    access.ensure_context :resource
    access.allow(:user_copilot_space_editor) { |context| context[:resource].owner.try(:user?) }
  end

  # The resource is a copilot space owned by user
  # Only the space owner or users with admin access can list collaborators
  define_access :list_user_copilot_space_collaborators do |access|
    access.ensure_context :resource
    access.allow(:user_copilot_space_collaborator_viewer) { |context| context[:resource].owner.try(:user?) }
  end

  # The resource is a copilot space owned by user
  # Only the space owner or users with admin access can manage the space
  define_access :manage_user_copilot_space do |access|
    access.ensure_context :resource
    access.allow(:user_copilot_space_manager) { |context| context[:resource].owner.try(:user?) }
  end

  # The resource is a copilot space owned by user
  # Only the space owner or users with admin access can manage collaborators
  define_access :manage_user_copilot_space_collaborators do |access|
    access.ensure_context :resource
    access.allow(:user_copilot_space_collaborator_manager) { |context| context[:resource].owner.try(:user?) }
  end

  # The resource is a copilot space owned by organization
  # Organization members with appropriate permissions can list collaborators
  define_access :list_organization_copilot_space_collaborators do |access|
    access.ensure_context :resource
    access.allow(:org_copilot_space_collaborator_viewer) { |context| context[:resource].owner.try(:organization?) }
  end

  # The resource is a copilot space owned by organization
  # Organization members with appropriate permissions can manage the space
  define_access :manage_organization_copilot_space do |access|
    access.ensure_context :resource
    access.allow(:org_copilot_space_manager) { |context| context[:resource].owner.try(:organization?) }
  end

  # The resource is a copilot space owned by organization
  # Organization members with appropriate permissions can manage collaborators
  define_access :manage_organization_copilot_space_collaborators do |access|
    access.ensure_context :resource
    access.allow(:org_copilot_space_collaborator_manager) { |context| context[:resource].owner.try(:organization?) }
  end
end
