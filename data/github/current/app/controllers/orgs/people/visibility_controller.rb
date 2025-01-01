# typed: true
# frozen_string_literal: true

class Orgs::People::VisibilityController < Orgs::Controller
  before_action :login_required
  before_action do
    T.bind(self, Orgs::People::VisibilityController)
    ensure_trade_restrictions_allows_org_member_management(fallback_location: org_people_url(this_organization))
  end

  def update
    members = User.where(id: params[:member_ids].split(","))
    if can_set_visibility?(members)
      publicize = params[:publicize].present?

      members.each do |member|
        if publicize
          this_organization.publicize_member(member)
        else
          this_organization.conceal_member(member)
        end
      end

      flash[:notice] = "You #{publicize ? 'publicized' : 'concealed'} #{members.size} #{"membership".pluralize(members.size)}."
    else
      flash[:notice] = "You're not allowed to do that."
    end

    redirect_to :back
  end

  private

  def can_set_visibility?(requested_users)
    if params[:publicize].present?
      return true if this_organization.can_publicize_memberships?(current_user, members: requested_users)
    elsif params[:conceal].present?
      return true if this_organization.can_conceal_memberships?(current_user, members: requested_users)
    end

    false
  end
end
