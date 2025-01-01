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
        this_organization.update_member(member, action: member_action)
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

  memoize def allowed_ids
    this_organization.member_ids
  end

  memoize def members
    User.where(id: provided_ids & allowed_ids)
  end
end
