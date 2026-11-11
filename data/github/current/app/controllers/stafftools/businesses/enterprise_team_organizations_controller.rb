# typed: strict
# frozen_string_literal: true

class Stafftools::Businesses::EnterpriseTeamOrganizationsController < Stafftools::Businesses::BusinessBaseController
  include ApplicationController::VerifiedFetchDependency
  allow_verified_fetch only: [:destroy, :update]

  skip_before_action :dotcom_required

  include ApplicationController::JsonDependency
  before_action :parse_json_params, only: [:update]

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
      killswitchEnabled: FeatureFlag.vexi.enabled?("enterprise_teams_killswitch", this_business, default: false),
      enterpriseTeam: {
        id: business_team.id,
        name: business_team.name,
        slug: business_team.slug,
        showRoute: stafftools_enterprise_team_path(this_business, business_team.id),
        organizationSelectionType: business_team.organization_selection_type,
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

  sig { void }
  def destroy
    T.unsafe(self).class.react_bundle_name = "business-teams"

    business_team = BusinessTeam.find_by(id: params[:enterprise_team_id])
    return render_404 if business_team.nil?

    synchronous = params[:synchronous] == "true"
    business_team.remove_from_organizations(org_ids: [params[:id]], synchronous_orchestration: synchronous)
    head 204
  end

  sig { void }
  def update
    T.unsafe(self).class.react_bundle_name = "business-teams"

    business_team = BusinessTeam.find_by(id: params[:enterprise_team_id])
    return render_404 if business_team.nil?

    selection_type = params[:organizationSelectionType]

    unless selection_type && BusinessTeam.organization_selection_types.key?(selection_type)
      return render json: { error: "Invalid organizationSelectionType" }, status: 422
    end

    begin
      result = EnterpriseTeams::Factory.update_business_team(
        enterprise: this_business,
        team_slug: business_team.slug,
        team_name: business_team.name,
        description: business_team.description,
        organization_selection_type: selection_type.to_sym,
        external_group_id: nil
      )
    rescue ActiveRecord::RecordInvalid => e
      return render(json: { data: { error: e.record.errors.full_messages.to_sentence } }, status: :bad_request)
    rescue EnterpriseTeams::Factory::BusinessTeamValidationError => e
      return render(json: { data: { error: e.message } }, status: :bad_request)
    rescue ArgumentError, KeyError, TypeError => e
      return render(json: { data: { error: "#{e.message}" } }, status: :bad_request)
    end
    head :no_content
  end
end
