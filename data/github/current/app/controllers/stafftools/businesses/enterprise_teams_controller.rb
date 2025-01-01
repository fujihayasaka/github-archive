# typed: strict
# frozen_string_literal: true

class Stafftools::Businesses::EnterpriseTeamsController < Stafftools::Businesses::BusinessBaseController
  extend T::Sig
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

  before_action :enterprise_teams_enabled?, only: [:index, :show, :database]

  sig { void }
  def index
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
  def show
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
  def database # rubocop:todo GitHub/UseRestfulActions
    team = this_business.enterprise_teams.unscoped.find_by(id: params[:id])
    return render_404 if team.nil?

    render "stafftools/businesses/enterprise_teams/database", locals: {
      enterprise_team: team
    }
  end

  private

  sig { void }
  def enterprise_teams_enabled?
    render_404 unless this_business.enterprise_teams_enabled?
  end
end
