# typed: true
# frozen_string_literal: true

class Orgs::People::MembersController < Orgs::Controller
  before_action :login_required
  before_action :organization_admin_required, except: :create
  before_action :organization_or_business_admin_required, only: :create
  before_action :sudo_filter, except: :destroy

  before_action only: :destroy do
    T.bind(self, Orgs::People::MembersController)
    ensure_trade_restrictions_allows_org_member_management(fallback_location: org_people_url(this_organization))
  end

  # Add a member directly to an org, and any selected teams.
  # For use when invites are disabled.
  def create
    return render_404 unless this_organization.bypass_org_invitations?

    member = User.find_by(id: params[:invitee_id])

    if member.blank?
      return render_404
    end

    if member.is_enterprise_managed? && member.enterprise_managed_business != this_organization.business
      return render_404
    end

    if !this_organization.two_factor_requirement_met_by?(member)
      flash[:error] = <<-FLASH
        #{this_organization} requires its members to have two-factor
        authentication enabled. #{member.display_login} must enable two-factor authentication
        in order to be added to the organization.
      FLASH

      return redirect_to user_path(this_organization)
    end

    if params[:role] == "admin"
      this_organization.add_admin(member, adder: current_user)
    elsif params[:role] == "direct_member"
      this_organization.add_member(member, adder: current_user)
    elsif params[:role] == "reinstate"
      restorable = Restorable::OrganizationUser.restorable(this_organization, member)
      this_organization.restore_membership(restorable, actor: current_user)
    else
      return render_404
    end

    teams = this_organization.teams.where(id: params[:team_ids])
    if current_user.can_add_members_for?(this_organization, teams: teams)
      teams.each do |team|
        team.add_member(member, adder: current_user)
      end
    else
      flash[:error] = "You do not have permission to add members to all of the selected teams."
      redirect_to org_edit_invitation_path(this_organization, member.display_login)
      return
    end

    if params[:role] == "reinstate"
      flash[:notice] = "Job queued to reinstate #{member.display_login} to #{this_organization.safe_profile_name}!"
    else
      flash[:notice] = "You've added #{member.display_login} to #{this_organization.safe_profile_name}!"
    end
    redirect_to org_people_path(this_organization)
  end

  def destroy
    users = User.where(id: params[:member_ids].split(",")).to_a

    # If the logged-in user is one of the members to be removed, put them at the
    # end in case all other owners are being removed.
    move_current_user_to_end(users)

    begin
      users.each do |user|
        if this_organization.direct_or_team_member?(user, include_indirect_abilities: true)
          this_organization.remove_member(user, background_team_remove_member: true)
        else
          this_organization.remove_direct_repo_access(user)
        end
      end
    rescue Organization::NoAdminsError
      flash[:error] = "You can't remove the last owner of this organization."
    rescue Organization::UnableToRemoveEmuError, Organization::UnableToRemoveEnterpriseTeamMemberError, Organization::BusinessTeamsDependency::UnableToRemoveBusinessTeamMemberError => error
      flash[:error] = error.message
    end

    unless flash[:error]
      flash[:notice] = "You've removed #{pluralize(users.length, "person")} from the organization. \
        It may take a few minutes for the removal to process. #{seats_reminder_on_removal(users.length)}".squish
    end

    if params[:redirect_to_path].present?
      safe_redirect_to params[:redirect_to_path]
    else
      redirect_to :back
    end
  end

  private

  def move_current_user_to_end(users)
    if users.include?(current_user)
      users.delete(current_user)
      users << current_user
    end
  end

  def seats_reminder_on_removal(users_removed)
    return unless GitHub.billing_enabled?
    return if this_organization.has_unlimited_seats?
    "If you no longer need #{users_removed == 1 ? "this seat" : "these seats"}, \
      please make sure to remove #{users_removed == 1 ? "it" : "them"} in your billing settings.".squish
  end
end
