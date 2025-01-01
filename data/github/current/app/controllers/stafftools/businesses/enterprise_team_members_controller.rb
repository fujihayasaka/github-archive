# typed: strict
# frozen_string_literal: true

class Stafftools::Businesses::EnterpriseTeamMembersController < Stafftools::Businesses::BusinessBaseController
  extend T::Sig
  include BusinessesHelper
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
    memberships = []
    if enterprise_team.direct_memberships_enabled?
      # No active record associations from User -> EnterpriseTeamMembership, have to start from ETM
      memberships = enterprise_team.enterprise_team_memberships
        .includes(:user)
        .where("users.login LIKE ?", "%#{query}%")
        .order("users.login")
        .paginate(page: current_page, per_page: PER_PAGE)
    end

    render "stafftools/businesses/enterprise_teams/direct_members", locals: {
      this_business: this_business,
      enterprise_team: enterprise_team,
      memberships: memberships,
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
