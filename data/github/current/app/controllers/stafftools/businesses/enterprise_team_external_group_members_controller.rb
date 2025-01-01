# typed: strict
# frozen_string_literal: true

class Stafftools::Businesses::EnterpriseTeamExternalGroupMembersController < Stafftools::Businesses::BusinessBaseController
  extend T::Sig
  skip_before_action :dotcom_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Billing,
    ApplicationRecord::Copilot,
    only: [:index]

  PER_PAGE = 30 # Rails default

  sig { void }
  def index
    enterprise_team = this_business.enterprise_teams.find_by(id: params[:enterprise_team_id])
    return render_404 if enterprise_team.nil?

    query = ActiveRecord::Base.sanitize_sql_like(params[:query].to_s.strip.downcase)
    member_ids = enterprise_team.member_user_ids
    members = User.where(id: member_ids).where("login LIKE ?", "%#{query}%").order(:login).paginate(page: current_page, per_page: PER_PAGE)

    render "stafftools/businesses/enterprise_teams/external_group_members", locals: {
      this_business: this_business,
      enterprise_team: enterprise_team,
      members: members,
    }
  end

  sig { params(page_param: Symbol).returns(Integer) }
  private def current_page(page_param = :page)
    if params[page_param].blank? || !params[page_param].respond_to?(:to_i)
      1
    else
      params[page_param].to_i.abs
    end
  end
end
