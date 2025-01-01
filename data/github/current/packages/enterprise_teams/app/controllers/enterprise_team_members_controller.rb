# typed: strict
# frozen_string_literal: true

class EnterpriseTeamMembersController < Businesses::BusinessController
  include ReactHelper
  include BusinessTeamHandlers
  include ApplicationController::VerifiedFetchDependency

  allow_verified_fetch only: [:index, :create, :destroy]

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = T.let([
    "EnterpriseTeamMembersController#create",
    "EnterpriseTeamMembersController#destroy",
  ].freeze, T::Array[String])

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    only: [:index, :create, :destroy]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :create, :destroy], optional: true

  before_action :enterprise_teams_enabled_required
  before_action :business_owner_required, except: [:index]
  before_action only: [:index] do
    T.bind(self, Businesses::Concerns::BusinessAccess)
    business_access_required(allow_members: true)
  end
  before_action :validate_team_parameter, only: [:index, :create, :destroy]
  before_action :validate_team_direct_membership_access, only: [:create, :destroy]
  before_action :validate_user_parameter, only: [:create, :destroy]
  before_action :validate_team_size_limit, only: [:create]

  skip_before_action :cap_pagination, only: %i(index)

  MAXIMUM_USERS_PER_TEAM = 50000
  MEMBERS_PER_PAGE = 30

  sig { void }
  def index
    # TODO: if / else for Business Team
    enterprise_teams_index
  end

  sig { void }
  def create
    # TODO: if / else for Business Team
    enterprise_teams_create
  end

  sig { void }
  def destroy
    # TODO: if / else for Business Team
    enterprise_teams_destroy
  end

  private

  sig { void }
  def enterprise_teams_index
    enterprise_team = T.must(get_enterprise_team)
    query_args = parse_query_string(query_param)

    business_members = EnterpriseTeams::Helper.filtered_members(T.must(current_user), enterprise_team, query: query_args[:query])
      .paginate(page: current_page, per_page: MEMBERS_PER_PAGE)

    respond_to do |format|
      format.html do
        is_owner = this_business.owner?(current_user)
        render "businesses/people/enterprise_team", locals: {
          enterprise_team: enterprise_team.attributes,
          direct_memberships_enabled: enterprise_team.direct_memberships_enabled?,
          page_size: MEMBERS_PER_PAGE,
          total_members: business_members.total_entries,
          members: business_members.map do |business_user|
            {
              id: GitHub.enterprise? ? business_user.id : business_user.user_id,
              name: business_user.name,
              login: business_user.display_login
            }
          end,
          member_suggestions_path: enterprise_team_member_suggestions_path(this_business),
          readonly: !is_owner,
          use_member_organizations_path_for_user_links: is_owner, # Only owners can see the member organizations page today
        }
      end
      format.json do
        render json: {
          members: business_members.map do |business_user|
            {
              id: GitHub.enterprise? ? business_user.id : business_user.user_id,
              name: business_user.name,
              login: business_user.display_login
            }
          end,
          total_members: business_members.total_entries,
          page_size: MEMBERS_PER_PAGE,
        }
      end
    end
  end

  sig { void }
  def enterprise_teams_create
    enterprise_team = T.must(get_enterprise_team)
    user_to_add = T.must(get_user_from_parameter)

    begin
      EnterpriseTeams::Helper.create_team_membership(enterprise_team, user_to_add)
      render(json: { data: {} })
    rescue ActiveRecord::RecordInvalid => e
      render(json: { data: { error: e.record.errors.messages.values.flatten.to_sentence } }, status: :bad_request)
    rescue ActiveRecord::RecordNotUnique => e
      render(json: { data: { error: "This user is already part of the enterprise team" } }, status: :bad_request)
    end
  end

  sig { void }
  def enterprise_teams_destroy
    enterprise_team = T.must(get_enterprise_team)
    user_to_remove = T.must(get_user_from_parameter)
    membership = enterprise_team.enterprise_team_memberships.find_by(user: user_to_remove)
    if membership.present?
      membership.destroy!
      render(json: { data: {} }, status: :ok)
    else
      render(json: { data: { error: "This user is not a member of the team." } }, status: :not_found)
    end
  end

  sig { void }
  def validate_team_parameter
    enterprise_team = get_enterprise_team
    unless enterprise_team.present?
      render(json: { data: { error: "Team not found." } }, status: :not_found)
    end
  end

  sig { void }
  def validate_team_direct_membership_access
    enterprise_team = get_enterprise_team
    return if enterprise_team.nil?
    unless enterprise_team.direct_memberships_enabled?
      render(json: { data: { error: "Team does not allow direct memberships." } }, status: :bad_request)
    end
  end

  sig { void }
  def validate_team_size_limit
    enterprise_team = get_enterprise_team
    if enterprise_team.present? && enterprise_team.member_user_ids.count >= MAXIMUM_USERS_PER_TEAM
      render(json: { data: { error: "This team has reached the limit of #{MAXIMUM_USERS_PER_TEAM} members." } })
    end
  end

  sig { void }
  def validate_user_parameter
    begin
      EnterpriseTeams::Helper.validate_user_parameter(current_business, params[:user_login])
    rescue ArgumentError => e
      render(json: { data: { error: e.message } }, status: :bad_request)
    rescue EnterpriseTeams::Helper::UserNotInEnterpriseError => e
      render(json: { data: { error: e.message } }, status: :not_found)
    end
  end

  sig { returns(T.nilable(EnterpriseTeam)) }
  memoize def get_enterprise_team
    current_business.enterprise_teams.active.find_by(slug: params[:team_slug])
  end

  sig { returns(T.nilable(User)) }
  memoize def get_user_from_parameter
    User.find_by_login(params[:user_login])
  end

  sig { void }
  def enterprise_teams_enabled_required
    # TODO: allow exclusion for Business Team enabled enterprises
    render_404 unless enterprise_teams_enabled?(current_business)
  end
end
