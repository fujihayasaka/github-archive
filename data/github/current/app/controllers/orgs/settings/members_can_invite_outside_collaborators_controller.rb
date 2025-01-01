# typed: true
# frozen_string_literal: true

class Orgs::Settings::MembersCanInviteOutsideCollaboratorsController < Orgs::Controller
  before_action :login_required
  before_action :org_admins_only
  after_action :customer_category_instrumentation

  def update
    if %w[0 1].include?(params[:members_can_invite_outside_collaborators])
      notice =
        if params[:members_can_invite_outside_collaborators] == "1"
          current_organization.allow_members_can_invite_outside_collaborators(actor: current_user)
          "Members can now #{helpers.invite_or_add_action_word.downcase} #{outside_collaborators_verbiage(current_organization)}."
        else
          current_organization.disallow_members_can_invite_outside_collaborators(actor: current_user)
          "Members will not be able to #{helpers.invite_or_add_action_word.downcase} #{outside_collaborators_verbiage(current_organization)}."
        end
      redirect_back(fallback_location: "/", notice: notice)
    else
      flash[:error] = "You specified an invalid value for the 'members can invite #{outside_collaborators_verbiage(current_organization)}' setting."
      redirect_back(fallback_location: "/")
    end
  end
end
