# typed: true
# frozen_string_literal: true

class Orgs::People::RoleController < Orgs::Controller
  before_action :login_required
  before_action :organization_admin_required
  before_action :sudo_filter
  before_action do
    T.bind(self, Orgs::People::RoleController)
    ensure_trade_restrictions_allows_org_member_management(fallback_location: org_people_url(this_organization))
  end

  def update
    case params[:role]
    when "admin"
      member_action = :admin

      notice = if members.size == 1
        "Made #{T.must(members.first).display_login} an owner."
      else
        "Made #{members.size} people owners."
      end
    when "direct_member"
      member_action = :read

      notice = if members.size == 1
        "Made #{T.must(members.first).display_login} a member."
      else
        "Made #{members.size} people members."
      end
    else
      flash[:error] = "You provided an invalid role."
      return redirect_to :back
    end

    begin
      members.each do |member|
        if feature_enterprise_teams_org_assignment_enabled?
          if direct_member_allowed_ids.include?(member.id)
            this_organization.update_member(member, action: member_action)
          else
            this_organization.add_member(member, action: member_action)
          end
        else
          this_organization.update_member(member, action: member_action)
        end
      end
    rescue Organization::NoAdminsError
      flash[:error] = "You can't remove the organization's last admin."
    else
      flash[:notice] = notice
    end

    redirect_to :back
  end

  private

  memoize def provided_ids
    params[:member_ids].split(",").map(&:to_i)
  end

  # todo: remove this when enterprise_teams_org_assignment ff rolls out
  memoize def allowed_ids
    this_organization.member_ids
  end

  memoize def direct_member_allowed_ids
    this_organization.member_ids(include_indirect_abilities: false)
  end

  memoize def indirect_member_allowed_ids
    this_organization.member_ids - direct_member_allowed_ids
  end

  memoize def feature_enterprise_teams_org_assignment_enabled?
    this_organization.business&.erp_feature_enabled?(:enterprise_teams_org_assignment)
  end

  memoize def members
    if feature_enterprise_teams_org_assignment_enabled?
      User.where(id: provided_ids & (direct_member_allowed_ids + indirect_member_allowed_ids))
    else
      User.where(id: provided_ids & allowed_ids)
    end
  end
end
