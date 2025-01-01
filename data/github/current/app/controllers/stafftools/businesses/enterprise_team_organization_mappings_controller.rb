# typed: strict
# frozen_string_literal: true

class Stafftools::Businesses::EnterpriseTeamOrganizationMappingsController < Stafftools::Businesses::BusinessBaseController
  include BusinessesHelper
  skip_before_action :dotcom_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Copilot,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Iam,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Notify,
    only: [:index]

  PER_PAGE = 30 # Rails default

  sig { void }
  def index
    enterprise_team = this_business.enterprise_teams.find_by(id: params[:enterprise_team_id])
    return render_404 unless validate_enterprise_team?(enterprise_team)

    query = ActiveRecord::Base.sanitize_sql_like(params[:query].to_s.strip.downcase)
    organization_mappings = enterprise_team.enterprise_team_organization_mappings
      .includes(:organization, :team)
      .where("users.login LIKE ?", "%#{query}%")
      .order("users.login")
      .paginate(page: current_page, per_page: PER_PAGE)

    ghas_enabled_organizations_ids = RepositorySecurityCenterConfig
      .where(ghas_enabled: true, owner_type: "ORGANIZATION")
      .distinct
      .pluck(:owner_id)

    unmapped_organization_ids = ghas_enabled_organizations_ids - enterprise_team.enterprise_team_organization_mappings.pluck(:organization_id)
    undestroyed_organization_mappings = enterprise_team.enterprise_team_organization_mappings.includes(team: :organization)

    non_granted_mappings = non_granted_mappings(undestroyed_organization_mappings.to_a).group_by { |mapping| mapping.team&.name }

    render "stafftools/businesses/enterprise_teams/organization_mappings", locals: {
      this_business: this_business,
      enterprise_team: enterprise_team,
      organization_mappings: organization_mappings,
      unmapped_organization_ids: unmapped_organization_ids,
      undestroyed_organization_mappings: undestroyed_organization_mappings,
      non_granted_mappings: non_granted_mappings,
    }
  end

  sig { void }
  def update
    enterprise_team = this_business.enterprise_teams.find_by(id: params[:enterprise_team_id])
    return render_404 unless validate_enterprise_team?(enterprise_team)

    enqueue_update_job(enterprise_team_id: enterprise_team.id)

    redirect_to stafftools_enterprise_team_organization_mappings_path(this_business, enterprise_team)
  end

  private

  sig { params(page_param: Symbol).returns(Integer) }
  def current_page(page_param = :page)
    if params[page_param].blank? || !params[page_param].respond_to?(:to_i)
      1
    else
      params[page_param].to_i.abs
    end
  end

  sig { params(enterprise_team: T.nilable(EnterpriseTeam)).returns(T::Boolean) }
  def validate_enterprise_team?(enterprise_team)
    return false unless EnterpriseTeam.enabled_for_organizations?(business: this_business)
    !enterprise_team.nil?
  end

  sig { params(job: T.untyped).returns(T::Boolean) }
  def validate_job?(job)
    !job.nil?
  end

  sig { params(enterprise_team_id: Integer).void }
  def enqueue_update_job(enterprise_team_id:)
    EnterpriseTeamOrganizationMappingJob.perform_later(enterprise_team_id)
    flash[:notice] = "Job enqueued"
  end

  sig { params(organization_mappings: T::Array[EnterpriseTeamOrganizationMapping]).returns(T::Array[EnterpriseTeamOrganizationMapping]) }
  def non_granted_mappings(organization_mappings)
    granted_team_ids = SecurityProduct::SecurityManagerRole.filter_granted(organization_mappings.map(&:team).compact_blank!).pluck(:id).to_set
    organization_mappings.reject do |mapping|
      granted_team_ids.include?(mapping.team_id) || !mapping.enterprise_team&.enterprise_team_assignments&.any? { |assignment| assignment.assignment_type == "security_manager" }
    end
  end
end
