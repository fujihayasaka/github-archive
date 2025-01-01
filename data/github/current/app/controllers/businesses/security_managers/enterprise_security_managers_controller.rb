# typed: strict
# frozen_string_literal: true

class Businesses::SecurityManagers::EnterpriseSecurityManagersController < Businesses::BusinessController
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency

  layout "layouts/react_business"

  before_action :enabled_for_organization_security_manager_required
  before_action :business_owner_required, except: [:index, :teams]
  before_action only: [:index, :teams] do
    T.bind(self, Businesses::SecurityManagers::EnterpriseSecurityManagersController)
    business_access_required(allow_members: true)
  end

  allow_verified_fetch only: [:destroy, :create, :assignment_suggestions, :teams]

  before_action :parse_json_params, only: [:create]

  PAGE_SIZE = 10

  sig { void }
  def index
    render_react_app(
      app_name: "security-managers",
      title: "Security managers · #{this_business.name}",
      payload: {
        readonly: !this_business.owner?(current_user),
        canRemoveTeams: !GitHub.esm_enabled?
      },
      page_data: { sidebar: :people, selected_link: :business_security_managers }
    )
  end

  sig { void }
  def destroy
    return render_404 if GitHub.esm_enabled?

    team = this_business.enterprise_teams.active.find_by(slug: params[:team_slug])
    return render_404 unless team

    EnterpriseTeam.transaction do
      team.sync_to_organizations = "disabled"
      team.save!
      EnterpriseTeams::Helper.configure_security_manager_sync(enterprise: this_business, enterprise_team: team, set_security_manager: false)
    end

    EnterpriseTeamOrganizationMappingJob.perform_later(team.id)

    head :no_content
  end

  sig { void }
  def create
    team_slug = params[:teamSlug]
    return render status: :bad_request, json: { error: "Missing required parameter: teamSlug" } unless team_slug.present?

    team = this_business.enterprise_teams.active.find_by(slug: team_slug)
    return render status: :not_found, json: { error: "Team with slug '#{team_slug}' not found" } unless team

    EnterpriseTeam.transaction do
      team.sync_to_organizations = "all"
      team.save!
      EnterpriseTeams::Helper.configure_security_manager_sync(
        enterprise: this_business,
        enterprise_team: team,
        set_security_manager: true,
      )
    end

    EnterpriseTeamOrganizationMappingJob.perform_later(team.id)
    send_assignment_email(team)

    head :no_content
  end

  sig { void }
  def assignment_suggestions # rubocop:disable GitHub/UseRestfulActions
    teams = this_business.enterprise_teams.active.exclude_having_assignment(:security_manager)
    render json: teams.map { |team| { name: team.name, slug: team.slug } }
  end

  sig { void }
  def teams # rubocop:disable GitHub/UseRestfulActions
    page = params[:page].to_i
    page = 1 if page < 1

    response = {}

    enterprise_teams_rel = EnterpriseTeam.active.owned_by(this_business)
      .filter_by_assignment_type(:security_manager)
      .then do |rel|
        if params[:search].present? && !params[:search].empty?
          rel.where("name LIKE ?", "%#{params[:search]}%")
        else
          rel
        end
      end
    count = enterprise_teams_rel.count
    response[:totalPages] = (count.to_f / PAGE_SIZE).ceil

    response[:teams] = enterprise_teams_rel
      .paginate(page: page, per_page: PAGE_SIZE)
      .map do |team|
      {
        name: team.name,
        slug: team.slug,
        path: enterprise_team_members_path(this_business.slug, team.slug),
      }
    end

    render json: response
  end

  private

  sig { params(enterprise_team: EnterpriseTeam).void }
  def send_assignment_email(enterprise_team)
    org_admins = T.must(enterprise_team.business).organization_members(action: :admin).to_a
    SecurityCenterMailer.enterprise_security_manager_assignment(
      users_to_email: org_admins,
      business: T.must(enterprise_team.business),
      enterprise_teams: [enterprise_team],
    ).deliver_now
  rescue => e # rubocop:disable Lint/GenericRescue
    # We don't want to mark the job as failed because of email. Log and swallow.
    Failbot.report(
      e,
      "gh.enterprise_team.id": enterprise_team.id,
      "gh.enterprise_team.business_id": enterprise_team.business_id,
    )
    GitHub.dogstats.increment("enterprise_team.assignment_job.error", tags: [
      "action:send_assignment_email"
    ])
  end

  sig { void }
  def enabled_for_organization_security_manager_required
    render_404 unless EnterpriseTeam.enabled_for_organization_security_manager?(current_business)
  end

  depends_on_clusters \
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Copilot,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    only: [:index, :assignment_suggestions, :teams]
end
