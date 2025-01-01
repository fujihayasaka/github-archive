# typed: true
# frozen_string_literal: true

class Orgs::TeamMembers::MemberView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  attr_reader :team, :member, :email, :invitation, :disable_bulk_actions, :graphql_team, :graphql_org, :graphql_member

  def team_maintainer?
    team.maintainer?(member)
  end

  def org_admin?
    organization.adminable_by?(member)
  end

  def show_team_poster_label?
    return false unless GitHub.flipper[:enhanced_team_posts].enabled?(organization)
    team.team_post_creatable_by?(member)
  end

  def role_change_item_enabled?(can_administer_team, can_administer_org)
    return false if org_admin?
    return true if can_administer_org

    can_administer_team && organization.direct_member?(member)
  end

  def show_remove_button?(leavable, ldap_mapped, adminable)
    return false if member == current_user && (leavable != "LEAVE")
    return false if ldap_mapped
    return false if invited?

    !!adminable
  end

  def invited?
    invitation.present?
  end

  def organization
    team.organization
  end

  def email_invitation?
    invited? && email.present?
  end

  def team_locally_managed?
    team.locally_managed?
  end

  # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
  def viewer_can_administer_team?
    @viewer_can_administer_team ||= team.adminable_by?(current_user)
  end

  def viewer_can_administer_org?
    @viewer_can_administer_org ||= organization.adminable_by?(current_user)
  end

  # rubocop:enable GitHub/BooleanMemoizationWithOrOperator

  def member_url
    if viewer_can_administer_org?
      "/orgs/#{organization.name_with_display_owner}/people/#{member_login}"
    else
      "/#{member_login}"
    end
  end

  def member_login
    member.display_login
  end
end
