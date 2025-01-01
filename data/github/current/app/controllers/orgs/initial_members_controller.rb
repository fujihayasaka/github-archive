# typed: true
# frozen_string_literal: true

class Orgs::InitialMembersController < Orgs::Controller
  before_action :login_required
  before_action :organization_admin_required
  before_action :bypass_org_invites_required

  def create
    member = User.find_by(login: params[:member])

    if this_organization.at_seat_limit?
      render json: {
        message_html: render_to_string(
          partial: "organizations/signup/seat_limit_error",
          formats: [:html],
          layout: false
        )
      }, status: :not_found
    else
      this_organization.add_member(member, adder: current_user)

      render json: {
        list_item_html: render_to_string(
          partial: "orgs/people/members_for_new_org",
          formats: [:html],
          locals: {
            user: member,
            organization: this_organization,
          }
        )
      }
    end
  end

  def destroy
    user = User.find_by(login: params[:member])

    begin
      this_organization.remove_member(user, background_team_remove_member: true)
    rescue Organization::NoAdminsError
      return render json: { error: "You can't remove the last owner of this organization." }, status: :not_found

    rescue Organization::UnableToRemoveEmuError, Organization::UnableToRemoveEnterpriseTeamMemberError, Organization::BusinessTeamsDependency::UnableToRemoveBusinessTeamMemberError => error
      return render json: { error: error.message }, status: :forbidden
    end

    head :ok
  end

  private

  def bypass_org_invites_required
    render_404 unless GitHub.bypass_org_invites_enabled?
  end
end
