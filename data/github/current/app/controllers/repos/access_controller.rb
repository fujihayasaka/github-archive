# typed: true
# frozen_string_literal: true

class Repos::AccessController < AbstractRepositoryController
  include GitHub::Memoizer
  include EnterpriseManagedUsersHelper

  before_action :check_repository_accessible
  before_action :redirect_legacy_collaborators, only: :index
  before_action :enforce_plan_supports_insights, only: [:index, :collaborators]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Billing,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Iam,
    ApplicationRecord::Spokes,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    only: [:collaborators]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Iam,
    ApplicationRecord::Spokes,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Ballast,
    ApplicationRecord::Memex,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Iam,
    ApplicationRecord::Billing,
    only: [:export]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :collaborators, :export],
    optional: true

  USERS_PER_PAGE = 30

  def index
    organization = current_repository.owner
    domain_emails_hash = if organization.plan_supports?(:display_verified_domain_emails) &&
        organization.terms_of_service.corporate?
      organization.email_eligible_domain_urls.any?
      organization.domain_emails_for_member_ids(member_ids: users_with_access.map(&:id))
    end

    respond_to do |format|
      format.html do
        if request.xhr?
          headers["Cache-Control"] = "no-cache, no-store"
          render partial: "repositories/people/people_table",
                 locals: { people: users_with_access, domain_emails_hash: domain_emails_hash, people_permission_hash: users_permission_hash }
        else
          render "repositories/people/index",
                 locals: { people: users_with_access, domain_emails_hash: domain_emails_hash, people_permission_hash: users_permission_hash }
        end
      end
    end
  end

  def collaborators # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.html do
        if request.xhr?
          headers["Cache-Control"] = "no-cache, no-store"
          render partial: "repositories/people/collaborator_table",
                 locals: { organization: current_repository.owner, outside_collaborators: outside_collaborators, people_permission_hash: collaborators_permission_hash }
        else
          render "repositories/people/collaborators",
                 locals: { outside_collaborators: outside_collaborators, people_permission_hash: collaborators_permission_hash }
        end
      end
    end
  end

  def export # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless current_repository.plan_supports?(:repo_access_export)

    report = Repository::AccessReport.new(repository: current_repository, viewer: current_user)

    response.headers["Content-Type"] = "text/csv"

    send_data \
      report.generate_csv,
      type:     "text/csv",
      filename: report.filename
  end

  private

  def check_repository_accessible
    return render_404 if current_repository.nil?
    return render_404 unless owner.organization?
    render_404 unless owner.adminable_by?(current_user)
  end

  def redirect_legacy_collaborators
    # Previously, the outside collaborators page was accessed via the same URL, but with a URL
    # param `affiliation=OUTSIDE`. If getting a call like that now, just redirect to the
    # /collaborators page
    if params[:affiliation] == "OUTSIDE"
      query_param = {}
      query_param[:query] = params[:query] unless params[:query].blank?
      redirect_to repo_people_collaborators_path(current_repository.owner.display_login,
                                                 current_repository.name, query_param)
    end
  end

  memoize def member_ids
    current_repository.direct_or_team_member_ids(
      viewer: current_user,
      immediate_only: false,
    )
  end

  memoize def collaborator_ids
    current_repository.outside_collaborators_ids
  end

  memoize def team_ids
    current_repository.teams.pluck(:id)
  end

  memoize def users_with_access
    filtered_users(user_ids: member_ids)
  end

  memoize def users_permission_hash
    find_user_permissions(user_ids: member_ids)
  end

  memoize def outside_collaborators
    filtered_users(user_ids: collaborator_ids)
  end

  memoize def collaborators_permission_hash
    find_user_permissions(user_ids: collaborator_ids)
  end

  # Takes an Array or Set of user ids
  # returns a hash of user ids to permissions which can be ability actions or (custom) role names
  def find_user_permissions(user_ids:)
    # Gets the direct and indirect user abilities
    user_abilities = Authorization::Queries::MostCapableAbilitiesBetweenMultipleActorsAndSubjects.new(
      actor_ids: user_ids.to_a,
      actor_type: User,
      subjects: [current_repository],
      subject_type: "Repository",
    ).execute

    user_permissions = Hash.new { |h, k| h[k] = "" }
    user_abilities.each do |ability|
      user_permissions[ability.actor_id] = ability.action if user_permissions[ability.actor_id].empty? || RepositoryRole.target_greater_than_or_equal_to_other_role?(target: user_permissions[ability.actor_id], other_role: ability.action.to_sym)
    end

    # used to get the highers ability
    team_abilities = Authorization::Queries::MostCapableAbilitiesBetweenMultipleActorsAndSubjects.new(
      actor_ids: team_ids.to_a,
      actor_type: Team,
      subjects: [current_repository],
      subject_type: "Repository",
    ).execute.pluck(:actor_id, :action).to_h

    # find all users to a team
    team_users = Ability.where(subject_type: Team, actor_type: User, subject_id: team_ids)
    team_users_hash = Hash.new { |h, k| h[k] = [] }

    team_users.each do |team_user|
      team_users_hash[team_user.subject_id] << team_user.actor_id
      team_ability = team_abilities[team_user.subject_id]
      user_permissions[team_user.actor_id] = team_ability if user_permissions[team_user.actor_id].empty? || RepositoryRole.target_greater_than_or_equal_to_other_role?(target: team_ability, other_role: user_permissions[team_user.actor_id].to_sym)
    end

    # Gets Custom Roles and System Roles like Triage and Maintain
    user_roles = UserRole.where(
      actor_type: "User", actor_id: user_ids,
      target_type: "Repository", target_id: current_repository.id
    )
    team_roles = UserRole.where(
      actor_type: "Team", actor_id: team_ids,
      target_type: "Repository", target_id: current_repository.id
    )

    user_team_roles = user_roles + team_roles

    include_custom_roles = owner.custom_roles_supported?

    user_team_roles.each do |role|
      user_role_ids = [role.actor_id]
      if role.actor_type == "Team"
        user_role_ids = team_users_hash[role.actor_id]
      end
      user_role_ids.each do |user_id|
        if role.role.custom?
          next if RepositoryRole.target_greater_than_or_equal_to_other_role?(target: user_permissions[user_id], other_role: role.role.base_role.name.to_sym)
          if include_custom_roles
            user_permissions[user_id] = role.role.name
          else
            user_permissions[user_id] = role.role.base_role.name
          end
        else
          next if RepositoryRole.target_greater_than_or_equal_to_other_role?(target: user_permissions[user_id], other_role: role.role.name.to_sym)
          user_permissions[user_id] = role.role.name
        end
      end
    end
    user_permissions
  end

  def filtered_users(user_ids:)
    users = User.where(id: user_ids)

    if params[:query].present?
      query = ActiveRecord::Base.sanitize_sql_like(params[:query].to_s.strip.downcase)
      if query.present?
        users = users.includes(:profile)
          .where(["users.login LIKE :query OR profiles.name LIKE :query", { query: "%#{query}%" }])
          .references(:profile)
      end
    end

    users.order(:login).paginate(page: current_page, per_page: USERS_PER_PAGE)
  end
end
