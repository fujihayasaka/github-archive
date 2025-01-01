# typed: strict
# frozen_string_literal: true

class Stafftools::Businesses::EnterpriseTeamsController < Stafftools::Businesses::BusinessBaseController
  include BusinessesHelper
  skip_before_action :dotcom_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Billing,
    ApplicationRecord::Ballast,
    only: [:index, :show, :database]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :show, :database],
    optional: true

  before_action :enterprise_or_business_teams_enabled?, only: [:index, :show, :database]

  sig { void }
  def index
    if using_business_teams?
      business_teams_index
    else
      enterprise_teams_index
    end
  end

  sig { void }
  def show
    if using_business_teams?
      business_teams_show
    else
      enterprise_teams_show
    end
  end

  sig { void }
  def database # rubocop:todo GitHub/UseRestfulActions
    if using_business_teams?
      business_teams_database
    else
      enterprise_teams_database
    end
  end

  private

  sig { void }
  def enterprise_teams_index
    enterprise_teams = EnterpriseTeam
      .unscoped
      .owned_by(this_business)
      .order(Arel.sql("deleted_at IS NOT NULL"), :deleted_at)

    if params[:query].present?
      enterprise_teams = enterprise_teams.where("name LIKE ?", "%#{params[:query]}%").order(:name)
    end

    render "stafftools/businesses/enterprise_teams/index", locals: {
      this_business: this_business,
      enterprise_teams: enterprise_teams.paginate(page: current_page, per_page: DEFAULT_PAGE_SIZE)
    }
  end

  sig { void }
  def business_teams_index
    enterprise_teams = this_business
      .business_teams
      .unscoped

    if params[:query].present?
      enterprise_teams = enterprise_teams.where("name LIKE ?", "%#{params[:query]}%").order(:name)
    end

    enterprise_teams = enterprise_teams.paginate(page: current_page, per_page: DEFAULT_PAGE_SIZE)

    payload = {
      businessSlug: this_business.slug,
      totalEntries: enterprise_teams.total_entries,
      totalPages: enterprise_teams.total_pages,
      enterpriseTeams: enterprise_teams.map do |enterprise_team|
        enterprise_team_react_payload(enterprise_team)
      end
    }

    T.unsafe(self).class.react_bundle_name = "business-teams"

    respond_to do |format|
      format.json do
        render json: payload
      end
      format.html do
        render_react_app(
          payload: payload,
          layout: "layouts/stafftools/business",
          title: "Enterprise team",
        )
      end
    end
  end

  sig { void }
  def enterprise_teams_show
    team = this_business.enterprise_teams.unscoped.find_by(id: params[:id])
    return render_404 if team.nil?

    external_groups = team.enterprise_team_group_mappings.map(&:external_group)
    render "stafftools/businesses/enterprise_teams/show", locals: {
      enterprise_team: team,
      external_groups: external_groups.paginate(page: current_page, per_page: DEFAULT_PAGE_SIZE),
      direct_members_count: team.direct_memberships_enabled? ? team.member_user_ids.count : 0,
      external_group_members_count: team.direct_memberships_enabled? ? 0 : team.member_user_ids.count
    }
  end

  sig { void }
  def business_teams_show
    team = this_business.business_teams.unscoped.find_by(id: params[:id])
    return render_404 if team.nil?

    T.unsafe(self).class.react_bundle_name = "business-teams"
    render_react_app(
      payload: {
        businessSlug: this_business.slug,
        enterpriseTeam: enterprise_team_react_payload(team)
      },
      layout: "layouts/stafftools/business",
      title: team.name,
    )
  end

  sig { void }
  def enterprise_teams_database
    team = this_business.enterprise_teams.unscoped.find_by(id: params[:id])
    return render_404 if team.nil?

    render "stafftools/businesses/enterprise_teams/database", locals: {
      enterprise_team: team
    }
  end

  sig { void }
  def business_teams_database
    team = this_business.business_teams.unscoped.find_by(id: params[:id])
    return render_404 if team.nil?

    render "stafftools/businesses/enterprise_teams/database", locals: {
      enterprise_team: team
    }
  end

  sig { returns(T::Boolean) }
  def using_business_teams?
    !!(!this_business.enterprise_teams_enabled? && BusinessTeam.enabled_for_enterprise?(business: this_business))
  end

  sig { void }
  def enterprise_or_business_teams_enabled?
    render_404 unless this_business.enterprise_teams_enabled? || BusinessTeam.enabled_for_enterprise?(business: this_business)
  end

  sig { params(business_team: BusinessTeam).returns(T::Hash[Symbol, T.untyped]) }
  def enterprise_team_react_payload(business_team)
    {
      id: business_team.id,
      name: business_team.name,
      slug: business_team.slug,
      externalGroupCount: 0,
      externalGroupMemberCount: 0,
      memberCount: business_team.members.count,
      organizationSelectionType: business_team.organization_selection_type,
      showRoute: stafftools_enterprise_team_path(this_business, business_team.id),
      databaseRoute: database_stafftools_enterprise_team_path(this_business, business_team.id),
      membersRoute: stafftools_enterprise_team_members_path(this_business, business_team.id)
    }
  end
end
