# typed: true
# frozen_string_literal: true

class Settings::Organization::Roles::EditView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  include Orgs::RolesHelper
  include Orgs::CustomRoleFormHelper

  include EnterpriseManagedUsersHelper
  include UrlHelpers

  attr_reader :base_role_fgps, :organization, :role

  delegate :base_role, :title_for, :icon_for, to: :base_role_fgps

  def role_invitation_count
    RepositoryInvitation.where(role_id: role.id).count
  end

  # do we need to inform the possibility of the org default role
  # being assigned to org members?
  def show_org_base_role_warning?
    role.org_member_count > 0 && (org_base_role != :none && org_base_role != :read)
  end
end
