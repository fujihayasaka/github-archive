# typed: strict
# frozen_string_literal: true

class Stafftools::Businesses::EnterpriseTeamOrganizationsController < Stafftools::Businesses::BusinessBaseController
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

  PER_PAGE = 30

  sig { void }
  def index
    T.unsafe(self).class.react_bundle_name = "business-teams"

    business_team = BusinessTeam.find_by(id: params[:enterprise_team_id])
    return render_404 if business_team.nil?

    query = ActiveRecord::Base.sanitize_sql_like(params[:query].to_s.strip.downcase)
    organizations = business_team.organizations
      .order("users.login")
      .where("users.login LIKE ?", "%#{query}%")
      .paginate(page: current_page, per_page: PER_PAGE)

    payload = {
      totalEntries: organizations.respond_to?(:total_entries) ? organizations.total_entries : 0,
      totalPages: organizations.respond_to?(:total_pages) ? organizations.total_pages : 1,
      businessSlug: this_business.slug,
      enterpriseTeam: {
        id: business_team.id,
        name: business_team.name,
        slug: business_team.slug,
        showRoute: stafftools_enterprise_team_path(this_business, business_team.id),
      },
      orgs: organizations.map do |org|
        {
          id: org.id,
          name: org.name,
          showRoute: stafftools_user_path(org),
        }
      end
    }

    respond_to do |format|
      format.json do
        render json: payload
      end
      format.html do
        render_react_app(
          payload: payload,
          layout: "layouts/stafftools/business",
        )
      end
    end
  end
end
