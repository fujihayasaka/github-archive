# typed: strict
# frozen_string_literal: true

class BusinessTeam < Team
  include T::Sig

  MAX_TEAM_NAME_LENGTH = 100
  MAX_TEAM_DESCRIPTION_LENGTH = 350

  belongs_to :business
  validates_presence_of :business

  has_many :business_team_org_assignments, inverse_of: :business_team

  validates :name, uniqueness: { scope: :business_id, case_sensitive: false }
  validates :name, length: { maximum: MAX_TEAM_NAME_LENGTH }
  validates :slug, uniqueness: { scope: :business_id, case_sensitive: true }
  validates :description, length: { maximum: MAX_TEAM_DESCRIPTION_LENGTH }

  has_many :selected_organizations,
    -> { merge(Organization.active) },
    through: :business_team_org_assignments,
    source: :organization,
    foreign_key: :team_id

  enum :privacy, { secret: 0, closed: 1 }, default: :closed
  enum :organization_selection_type, {
    disabled: 0,
    all: 1,
    selected: 2
  }, prefix: :org_assignment
  validates_inclusion_of :organization_selection_type, in: organization_selection_types.keys, message: "Invalid assignment type"

  validate :validate_absence_of_persisted_organization_id
  validate :business_team_limit_can_create_more_teams, on: :create

  default_scope { unscope(where: :organization_id) }

  LABEL_NAME = T.let("Enterprise team".freeze, String)

  ENTERPRISE_SLUG_PREFIX = T.let("ent:".freeze, String)

  sig { override.returns(T::Boolean) }
  def business_team?
    true
  end

  ## Since we are using a polymorphic belongs to association in UserRole, we are setting the polymorphic name here
  ## to resolve the association scope and foreign association type as BusinessTeam instead of the base class of Team
  ## see: https://github.com/rails/rails/blob/0efc3e899a0cade4e1b7c626d1df043dadf2d2a2/activerecord/lib/active_record/inheritance.rb#L211
  sig { returns(String) }
  def self.polymorphic_name
    self.sti_name
  end

  sig { returns(::Symbol) }
  def self.hydro_context
    :BUSINESS_TEAM
  end

  sig { params(business: T.nilable(Business)).returns(T::Boolean) }
  def self.enabled_for_enterprise?(business:)
    return false if business.nil?
    return false if EnterpriseTeam.enabled_for_organizations?(business: business)
    business.erp_feature_enabled?(:enterprise_teams_crud)
  end

  sig { returns(T::Array[Integer]) }
  def organization_ids
    case organization_selection_type.to_sym
    when :all
      T.must(business).organization_ids
    when :selected
      selected_organization_ids
    else
      []
    end
  end

  ## overrides Team method with the same name to check if the team is associated with an organization
  sig { params(organization: Organization).returns(T::Boolean) }
  def is_associated_with_organization?(organization)
    return false unless T.must(business).erp_feature_enabled?(:enterprise_teams_org_assignment)
    case organization_selection_type.to_sym
    when :all
      organization.business&.id == business_id
    when :selected
      self.selected_organizations.where(id: organization.id).any?
    else
      false
    end
  end

  sig { params(org_ids: T::Array[Integer], bypass_org_assignment_selection_requirement: T::Boolean).void }
  def add_to_organizations(org_ids:, bypass_org_assignment_selection_requirement: false)
    # Sync all does not use BusinessTeamOrgAssignment, disabled means no orgs
    return if !org_assignment_selected? && !bypass_org_assignment_selection_requirement

    org_ids.compact!
    org_ids = T.must(business).organizations.where(id: org_ids).ids
    return if org_ids.empty?

    new_org_ids = if bypass_org_assignment_selection_requirement
      org_ids
    else
      org_ids - organization_ids
    end.take(organization_assignments_allowed_to_add)
    return if new_org_ids.empty?

    new_org_ids.map do |org_id|
      {
        team_id: id,
        organization_id: org_id,
      }
    end.each_slice(100) do |batch|
      with_write do
        BusinessTeamOrgAssignment.throttle do
          BusinessTeamOrgAssignment.insert_all(batch)
        end
      end
    end

    members_or_organizations_updated(action: :add, operation: :org)
  end

  sig { params(org_ids: T::Array[Integer]).void }
  def remove_from_organizations(org_ids:)
    return unless org_assignment_selected?

    with_write { BusinessTeamOrgAssignment.where(team_id: id, organization_id: org_ids).destroy_all }

    members_or_organizations_updated(action: :remove, operation: :org)
  end

  sig { params(users: T::Array[User], options: T::Hash[Symbol, T.untyped]).returns(Team::AddMemberStatus) }
  def bulk_add_members(users, options = {})
    return Team::AddMemberStatus::NOT_USER if users.empty?

    return Team::AddMemberStatus::NO_PERMISSION unless self.class.enabled_for_enterprise?(business: business)

    caller_type = T.let(options[:caller_type], T.nilable(Symbol))
    return AddMemberStatus::ENTERPRISE_TEAM_MANAGED unless caller_type == :business_team

    # Filter out adding a user to a team if the user is not a member of the business
    valid_user_ids = if GitHub.single_business_environment?
      T.must(business).single_business_members.where(id: users.map(&:id)).pluck(:id)
    else
      T.must(business).user_accounts.where(user_id: users.map(&:id)).pluck(:user_id)
    end

    # Remove users that are not part of the new user_ids
    users.select! { |user| valid_user_ids.include?(user.id) }
    users = users.take(members_allowed_to_add)

    options = options.merge({
      skip_create_organization_memberships: true,
      skip_license_usage_update: true,
      caller_type: caller_type,
    })
    result = super(users, options)
    members_or_organizations_updated(action: :add, operation: :member, user_ids: valid_user_ids)
    result
  end

  # TODO: This is a placeholder for now to mitigate unknown risks of bulk_add_members_with_failover.
  # We can adjust this method as we learn more about the risks and requirements.
  sig { params(users: T::Array[User], options: T::Hash[Symbol, T.untyped]).returns(T::Array[Team::AddMemberStatus]) }
  def bulk_add_members_with_failover(users, options = {})
    [bulk_add_members(users, options)]
  end

  # TODO: This is a placeholder for now to mitigate unknown risks of singular member add.
  # We can adjust this method as we learn more about the risks and requirements.
  sig { params(user: User, options: T::Hash[Symbol, T.untyped]).returns(Team::AddMemberStatus) }
  def add_member(user, options = {})
    bulk_add_members([user], options)
  end

  sig { params(viewer: T.nilable(User), query: String).returns(ActiveRecord::Relation) }
  def eligible_members_in_enterprise(viewer, query: "")
    return User.none if business.nil?
    safe_business = T.must(business)

    eligible_members = safe_business.filtered_members(
      viewer,
      query: query,
      business_user_accounts_query: safe_business.supports_unaffiliated_user_accounts?,
      include_unaffiliated: true,
      deployment: "cloud"
    )
    eligible_members = User.where(id: eligible_members.pluck(:user_id)) if eligible_members.klass == BusinessUserAccount
    eligible_members = eligible_members.where.not(login: safe_business.shortcode + "_admin") unless safe_business.shortcode.nil?
    eligible_members.where.not(id: self.member_ids).order(:login)
  end

  sig { params(candidate: String).returns(T::Boolean) }
  private def any_conflicting_slugs?(candidate)
    scope = self.class.where(business_id: business_id, slug: candidate)
    scope = scope.where("id <> ?", id) unless new_record?

    scope.any?
  end

  # Public: Returns a uniquely identifiable slug for an Enterprise / Team combination
  #
  # TODO: This is a placeholder override for now since we don't have product specs yet, and otherwise can not
  # initialize an org-less team.
  #
  # Returns the slug
  sig { returns(String) }
  def combined_slug
    "/#{slug}"
  end
  alias_method :to_s, :combined_slug

  # Public: Returns either the User who created the team, or the Business that the team
  # belongs to.
  #
  # This method is mostly going to be used for front-end display purposes.
  sig { returns(T.nilable(T.any(User, Business))) }
  def creator
    super || business
  end

  sig { returns(T.nilable(Business)) }
  def target_for_conditional_access
    # In the CAP framework, TFCA refers to the entity governing
    # the conditional access rules that grant access to resources they own.
    # If any changes are done to this method, please loop in @github/authorization.
    # https://thehub.github.com/engineering/development-and-ops/dotcom/cap/how-does-cap-evaluation-work/#target-for-conditional-access-tfca
    business
  end

  # TODO: No-op for now, since we will not be targetting SCIM based Enterprises until now
  #
  # See Team.bulk_validate_add_member_users for override context
  sig { params(users: T::Array[User]).returns(T.nilable(Team::AddMemberStatus)) }
  private def bulk_validate_add_member_scim_restrictions(users:)
    nil
  end

  sig { params(options: T::Hash[Symbol, T.untyped]).void }
  private def assert_bulk_add_members_valid_option_keys(options)
    options.assert_valid_keys(:adder, :skip_license_usage_update, :skip_organization_seat_checks, :force_emu, :limit, :caller_type, :send_notification, :skip_user_synchronize_index, :synchronous_orchestration, :skip_create_organization_memberships)
  end

  sig { returns(T.nilable(Integer)) }
  def licensed_customer_id
    business&.customer_id || business&.customer&.id
  end

  sig { params(user: User, force: T::Boolean, send_notification: T::Boolean, team_destroyed: T::Boolean, queue_delete_jobs: T::Boolean, caller_type: T.nilable(Symbol)).void }
  def remove_member(user, force: false, send_notification: true, team_destroyed: false, queue_delete_jobs: true, caller_type: nil)
    bulk_remove_members(users: [user], force:, send_notification:, team_destroyed:, queue_delete_jobs:, caller_type:)
  end

  sig do override.params(
    users: T.any(ActiveRecord::Relation, T::Array[User]),
    force: T::Boolean,
    send_notification: T::Boolean,
    team_destroyed: T::Boolean,
    queue_delete_jobs: T::Boolean,
    caller_type: T.nilable(Symbol)).returns(T::Hash[Integer, Symbol])
  end
  def bulk_remove_members(users:, force: false, send_notification: true, team_destroyed: false, queue_delete_jobs: true, caller_type: nil)
    user_status = T.let(users.to_h { |user| [user.id, NOT_ALLOWED] }, T::Hash[Integer, Symbol])
    return user_status unless caller_type == :business_team
    result = super
    members_or_organizations_updated(action: :remove, operation: :member, user_ids: users.map(&:id))
    result
  end
  # TODO: BusinessTeam inheritance is not implemented yet,
  # so this method returns only returns repo ids
  # that the team has direct abilities for.
  # This method should likely be replaced with a reworked
  # method in the Team class which supports both team types.
  sig { params(affiliation: Symbol, sort: T::Hash[Symbol, Symbol], action: T::Array[Symbol]).returns(T::Array[Integer]) }
  def direct_or_inherited_repo_ids(affiliation: :all, sort: {}, action: [])
    raise "Not Implemented" if affiliation == :inherited

    team_id = self.id
    qry = Ability.where(
      actor_type: "BusinessTeam",
      actor_id: team_id,
      subject_type: "Repository",
      priority: Ability.priorities[:direct],
    )

    qry = qry.where(action: action) unless action.empty?
    qry = qry.order(sort) unless sort.empty?

    qry.pluck(:subject_id)
  end

  # TODO: this is a placeholder implementation
  # business team specific logic and errors should be added
  sig { override.params(repo: Repository, perm: T.any(String, Symbol), allow_different_owner: T::Boolean, repo_ids: T::Array[Integer]).returns(ModifyRepositoryStatus) }
  def add_repository(repo, perm, allow_different_owner: true, repo_ids: repository_ids)
    return ModifyRepositoryStatus::NOT_OWNED unless repo.organization_id
    unless is_associated_with_organization?(T.cast(repo.owner, Organization))
      return ModifyRepositoryStatus::NOT_OWNED
    end

    super
  end

  # TODO: this is a placeholder implementation
  # business team specific logic and errors should be added
  sig { override.params(repo: Repository, inline_fork_cleanup: T::Boolean).void }
  def remove_repository(repo, inline_fork_cleanup: false)
    repo.remove_team self
    repo.reload # clear cached associations, e.g. list of teams
  end

  # TODO: this is a placeholder implementation
  # business team specific logic and errors should be added
  sig { params(repo: Repository, perm: T.any(String, Symbol), context: T::Hash[Symbol, T.untyped]).returns(ModifyRepositoryStatus) }
  def update_repository_permission(repo, perm, context: {})

    # Only permit org-owned repos that belong to the current business
    if repo.business != business
      return ModifyRepositoryStatus::NOT_OWNED
    end

    # only allow input action in the ability format
    repo_permission_role = RepositoryRole.by_name(perm: perm, org: repo.owner)

    if repo_permission_role.nil?
      return ModifyRepositoryStatus::NO_PERMISSION
    end

    #Force apply the changes
    begin
      ActiveRecord::Base.connected_to(role: :writing) { repo.add_team self, action: repo_permission_role.name.to_sym }
    rescue ActiveRecord::RecordNotUnique
      ModifyRepositoryStatus::DUPE
    rescue ActiveRecord::RecordInvalid => e
      return ModifyRepositoryStatus::DUPE if e.message.include?("has already been taken")
      raise e
    end

    ModifyRepositoryStatus::SUCCESS
  end

  sig { override.params(user: T.nilable(User)).returns(Promise[T::Boolean]) }
  def async_visible_to?(user)
    return Promise.resolve(T.let(false, T::Boolean)) unless business
    T.must(business).async_member?(user)
  end

  sig { returns(T::Boolean) }
  def business_teams_limit_reached?
    return false unless business.present?
    T.must(business).business_teams_limit_reached?
  end

  sig { returns(Integer) }
  def limit_members_in_team
    return GitHub.business_team_member_limit unless business.present?
    T.must(business).business_team_member_limit
  end

  sig { returns(Integer) }
  def members_allowed_to_add
    limit_members_in_team - members_count
  end

  sig { returns(T::Boolean) }
  def member_limit_reached?
    members_count >= limit_members_in_team
  end

  sig { returns(Integer) }
  def limit_organization_assignments
    return GitHub.business_team_organization_assignment_limit unless business.present?
    T.must(business).business_team_organization_assignment_limit
  end

  sig { returns(Integer) }
  def organization_assignments_allowed_to_add
    limit_organization_assignments - selected_organizations.count
  end

  sig { returns(T::Boolean) }
  def organization_assignment_limit_reached?
    return false unless business.present?
    selected_organizations.count >= limit_organization_assignments
  end

  sig { override.returns(String) }
  def tenant_slug_for_avatar
    return "" unless GitHub.multi_tenant_enterprise?
    business&.slug
  end

  sig { void }
  private def business_team_limit_can_create_more_teams
    errors.add(:business, "team creation limit reached") if business_teams_limit_reached?
  end

  sig { override.returns(T::Boolean) }
  def locally_managed?
    false
  end

  sig { override.returns(T.nilable(Organization)) }
  def organization
    @organization_context
  end

  sig { override.returns(Promise[T.nilable(::Organization)]) }
  def async_organization
    Promise.resolve(@organization_context)
  end

  sig { override.returns(T.nilable(Integer)) }
  def organization_id
    @organization_context&.id
  end

  # Set org context for a business team so that methods like team.organization behaves like organization teams.
  # By default, it checks if the team is associated with the org.
  # The parameter to bypass the check is only meaant for the batch method to skip it as the batch method checks
  # all organizations at once, it should not be skipped if setting the context just for 1 team.
  sig { params(organization: Organization, check_association: T::Boolean).void }
  def set_organization_context(organization, check_association: true)
    return if check_association && !is_associated_with_organization?(organization)
    @organization_context = T.let(organization, T.nilable(Organization))
  end

  sig { override.returns(String) }
  def slug
    "#{ENTERPRISE_SLUG_PREFIX}#{super}"
  end

  sig { params(slug: String).returns(String) }
  def self.to_model_slug(slug)
    slug.delete_prefix(ENTERPRISE_SLUG_PREFIX)
  end

  sig { override.params(user: User).returns(T::Boolean) }
  def can_add_repositories?(user)
    @organization_context&.adminable_by?(user) || super
  end

  sig { params(teams: T.any(ActiveRecord::Relation, T::Array[Team]), organization: Organization).void }
  def self.set_organization_context_for_business_teams(teams, organization)
    business = organization.business
    return if business.nil?

    business_teams = teams.select { |t| t.is_a?(BusinessTeam) }
    return if business_teams.empty?

    teams_by_type = business_teams.group_by(&:organization_selection_type)

    # For :all, check business_id match
    teams_by_type["all"]&.each do |team|
      team.set_organization_context(organization, check_association: false) if team.business_id == business.id
    end

    # For :selected, fetch all selected org assignments in one query
    selected_teams = teams_by_type["selected"]
    if selected_teams&.any?
      teams_by_id = selected_teams.index_by(&:id)
      assigned_team_ids = BusinessTeamOrgAssignment.where(team_id: teams_by_id.keys, organization_id: organization.id).pluck(:team_id)
      assigned_team_ids.each do |team_id|
        teams_by_id[team_id]&.set_organization_context(organization, check_association: false)
      end
    end
  end

  sig { params(action: Symbol, operation: Symbol, user_ids: T.nilable(T::Array[Integer])).void }
  def members_or_organizations_updated(action:, operation:, user_ids: nil)
    return if GitHub.single_business_environment?
    BusinessUserAccountUpdateAttributesJob.perform_later(T.must(business), user_account_ids: T.must(business).user_accounts.where(user_id: user_ids || member_ids).pluck(:id))

    if operation == :org || operation == :team
      GlobalInstrumenter.instrument("business_team.enablement_toggled", {
        consuming_license: action == :add,
        business_team: self,
      })
    end
  end

  sig { void }
  private def validate_absence_of_persisted_organization_id
    errors.add(:organization_id, "must be absent") if read_attribute(:organization_id).present?
  end

  # Absolute permalink URL for this team.
  #
  # include_host - Prepend the endpoint with `GitHub.url`. By default this is `true`.
  sig { override.params(include_host: T::Boolean).returns(String) }
  def permalink(include_host: true)
    return super if @organization_context

    endpoint = "/enterprises/#{T.must(business).slug}/teams/#{slug}"

    if include_host
      "#{GitHub.url}#{endpoint}"
    else
      endpoint
    end
  end
end
