# typed: strict
# frozen_string_literal: true

class BusinessTeam < Team
  include T::Sig

  LABEL_NAME = T.let("Enterprise team".freeze, String)
  ENTERPRISE_SLUG_PREFIX = T.let("ent:".freeze, String)

  MAX_TEAM_NAME_LENGTH = 100
  MAX_TEAM_DESCRIPTION_LENGTH = 350

  BATCH_SIZE = 100
  LICENSE_JOB_DELAY_SECONDS = 60

  USER_ROLE_TARGET_TYPE = T.let("BusinessTeam".freeze, String)

  belongs_to :business
  validates_presence_of :business

  has_many :business_team_org_assignments, inverse_of: :business_team

  validates :name, uniqueness: { scope: :business_id, case_sensitive: false }
  validates :name, length: { maximum: MAX_TEAM_NAME_LENGTH }
  validates :slug, uniqueness: { scope: :business_id, case_sensitive: true }
  validates :description, length: { maximum: MAX_TEAM_DESCRIPTION_LENGTH }

  before_save :handle_org_selection_type_changed, if: :will_save_change_to_organization_selection_type?
  after_commit :organization_selection_type_updated, on: [:create, :update]

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

  # The class name persisted as `target_type` when a UserRole is created
  # with this object as target.
  #
  # Returns: String
  sig { returns(String) }
  def self.user_role_target_type
    USER_ROLE_TARGET_TYPE
  end

  sig { returns(::Symbol) }
  def self.hydro_context
    :BUSINESS_TEAM
  end

  sig { params(business: T.nilable(Business)).returns(T::Boolean) }
  def self.enabled_for_enterprise?(business:)
    return false if business.nil?
    return false if business.seats_plan_basic?
    return false if EnterpriseTeam.enabled_for_organizations?(business: business)
    business.erp_feature_enabled?(:enterprise_teams_crud)
  end

  sig { returns(String) }
  def self.remove_indirect_organization_membership_notice
    "Only direct organization memberships will be removed. Users with indirect organization \
    membership through an enterprise team will need to be removed from the team instead.".squish
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

  sig { void }
  private def handle_org_selection_type_changed
    @org_selection_type_changed = T.let(true, T.nilable(T::Boolean))
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

  sig { params(org_ids: T::Array[Integer], bypass_org_assignment_selection_requirement: T::Boolean, synchronous_orchestration: T::Boolean).returns(Team::AddOrganizationStatus) }
  def add_to_organizations(org_ids:, bypass_org_assignment_selection_requirement: false, synchronous_orchestration: false)
    # Sync all does not use BusinessTeamOrgAssignment, disabled means no orgs
    success = Team::AddOrganizationStatus::SUCCESS
    return success if !org_assignment_selected? && !bypass_org_assignment_selection_requirement

    org_ids.compact!
    business = T.must(self.business)
    org_ids = business.organizations.where(id: org_ids).ids
    return success if org_ids.empty?

    new_org_ids = if bypass_org_assignment_selection_requirement
      org_ids
    else
      org_ids - organization_ids
    end.take(organization_assignments_allowed_to_add)
    return success if new_org_ids.empty?

    status = bulk_validate_add_member_seats(member_ids, is_add_org_check: true)
    return status if status.is_a?(Team::AddOrganizationStatus) && status.error?

    TeamOrchestration.add_business_team_organizations(
      team: self,
      business_id: business_id,
      organization_ids: new_org_ids,
      skip_instrumentation: bypass_org_assignment_selection_requirement
    ).execute(synchronous: synchronous_orchestration)

    success
  end

  sig { params(org_ids: T::Array[Integer], synchronous_orchestration: T::Boolean).void }
  def remove_from_organizations(org_ids:, synchronous_orchestration: false)
    return unless org_assignment_selected?

    TeamOrchestration.remove_business_team_organizations(
      team: self,
      business_id: business_id,
      organization_ids: org_ids
    ).execute(synchronous: synchronous_orchestration)
  end

  # Unlike organization_ids.any?, this method adds a limit 1 to the generated SQL query while organization_ids fetches the entire org list and apply any? on an array
  sig { returns(T::Boolean) }
  def has_any_orgs?
    (org_assignment_selected? && selected_organizations.exists?) || !!(org_assignment_all? && business&.organizations&.exists?)
  end

  sig { params(user_ids: T::Array[Integer], is_add_org_check: T::Boolean).returns(T.any(Team::AddMemberStatus, Team::AddOrganizationStatus, T::Boolean)) }
  def bulk_validate_add_member_seats(user_ids, is_add_org_check: false)
    start_time = Time.current.utc
    business = T.must(self.business)
    has_orgs = is_add_org_check || has_any_orgs?

    if user_ids.any? && has_orgs && !business.has_unlimited_seats? && !GitHub.single_business_environment?
      if !business.has_sufficient_licenses_for_users?(user_ids: user_ids)
        return is_add_org_check ? Team::AddOrganizationStatus::NO_SEAT : Team::AddMemberStatus::NO_SEAT
      end
      if !business.has_sufficient_licenses_for_users?(user_ids: user_ids, pending_cycle: true)
        return is_add_org_check ? Team::AddOrganizationStatus::PENDING_CYCLE_NO_SEAT : Team::AddMemberStatus::PENDING_CYCLE_NO_SEAT
      end
    end
    GitHub.logger.info(
      "business_team.bulk_validate_add_member_seats.latency",
      "gh.business.id": business.id,
      "gh.user_ids.size": user_ids.size,
      "gh.duration_ms": (Time.current.utc - start_time) * 1000,
    )
    has_orgs
  end

  sig { params(users: T::Array[User], options: T::Hash[Symbol, T.untyped]).returns(Team::AddMemberStatus) }
  def bulk_add_members(users, options = {})
    if options[:called_from_orchestration]
      options = options.merge({
        skip_create_organization_memberships: true,
        skip_license_usage_update: true,
        caller_type: :business_team,
      })
      return super(users, options)
    end

    return Team::AddMemberStatus::NOT_USER if users.empty?

    return Team::AddMemberStatus::NO_PERMISSION unless self.class.enabled_for_enterprise?(business: business)

    caller_type = T.let(options[:caller_type], T.nilable(Symbol))
    return AddMemberStatus::ENTERPRISE_TEAM_MANAGED unless caller_type == :business_team

    # Filter out adding a user to a team if the user is not a member of the business
    business = T.must(self.business)
    valid_user_ids = if GitHub.single_business_environment?
      business.single_business_members.where(id: users.map(&:id)).pluck(:id)
    else
      business.user_accounts.where(user_id: users.map(&:id)).pluck(:user_id)
    end

    # Remove users that are not part of the new user_ids
    users.select! { |user| valid_user_ids.include?(user.id) }
    users = users.take(members_allowed_to_add)
    user_ids_to_add = users.map(&:id)
    validate_result = bulk_validate_add_member_seats(user_ids_to_add)
    return validate_result if validate_result.is_a?(Team::AddMemberStatus) && validate_result.error?
    has_orgs = validate_result

    options = options.merge({
      skip_create_organization_memberships: true,
      skip_license_usage_update: true,
      caller_type: caller_type,
    })

    actor = options.delete(:actor) || options.delete(:adder)
    orchestration = TeamOrchestration.add_business_team_members(
      team: self,
      business_id: business_id,
      user_ids: user_ids_to_add,
      options: options.merge(has_orgs: has_orgs == true),
      actor: actor
    )
    orchestration.execute(synchronous: options[:synchronous_orchestration] || false)
    Team::AddMemberStatus.new(orchestration.data[:result])
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
      include_outside_collaborators: true,
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

  # Public: Determine if orchestrations should be used for this team.
  #
  # Returns Boolean
  sig { override.returns(T::Boolean) }
  def use_team_orchestrations?
    true
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

  sig { returns(T::Boolean) }
  def assigned_enterprise_security_manager?
    UserRole.exists?(role: Role.enterprise_security_manager_role, actor: self, target: business)
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

  sig do
    override.params(
      users: T.any(ActiveRecord::Relation, T::Array[User]),
      force: T::Boolean,
      send_notification: T::Boolean,
      team_destroyed: T::Boolean,
      queue_delete_jobs: T::Boolean,
      caller_type: T.nilable(Symbol),
      called_from_orchestration: T::Boolean,
      skip_remove_organization_memberships: T::Boolean,
      synchronous_orchestration: T::Boolean
    ).returns(T::Hash[Integer, Symbol])
  end
  def bulk_remove_members(users:, force: false, send_notification: true, team_destroyed: false, queue_delete_jobs: true, caller_type: nil, called_from_orchestration: false, skip_remove_organization_memberships: true, synchronous_orchestration: false)
    if called_from_orchestration
      return super(users:, force:, send_notification:, team_destroyed:, queue_delete_jobs:, caller_type:, skip_remove_organization_memberships:)
    end
    user_status = T.let(users.to_h { |user| [user.id, NOT_ALLOWED] }, T::Hash[Integer, Symbol])
    return user_status unless caller_type == :business_team

    orchestration = TeamOrchestration.remove_business_team_members(
      team: self,
      business_id: business_id,
      user_ids: users.pluck(:id),
      options: {
        force: force,
        send_notification: send_notification,
        team_destroyed: team_destroyed,
        queue_delete_jobs: queue_delete_jobs
      }
    )
    orchestration.execute(synchronous: synchronous_orchestration)
    orchestration.data[:result] || {}
  end
  # TODO: BusinessTeam inheritance is not implemented yet,
  # so this method returns only returns repo ids
  # that the team has direct abilities for.
  # This method should likely be replaced with a reworked
  # method in the Team class which supports both team types.
  sig { params(affiliation: Symbol, sort: T::Hash[Symbol, Symbol], action: T::Array[Symbol]).returns(T::Array[Integer]) }
  def direct_or_inherited_repo_ids(affiliation: :all, sort: {}, action: [])
    BusinessTeam.direct_or_inherited_repo_ids(team_id: self.id, affiliation: affiliation, sort: sort, action: action)
  end

  sig { params(team_id: Integer, affiliation: Symbol, sort: T::Hash[Symbol, Symbol], action: T::Array[Symbol]).returns(T::Array[Integer]) }
  def self.direct_or_inherited_repo_ids(team_id:, affiliation: :all, sort: {}, action: [])
    raise "Not Implemented" if affiliation == :inherited

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
    # clear cached associations, e.g. list of teams
    if FeatureFlag.vexi.enabled?(:repos_domain_reload, default: false)
      Repositories.domain.reload(repo)
    else
      repo.reload
    end
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
    return super if organization.present? && user&.can_have_granular_permissions?

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

  sig { void }
  private def organization_selection_type_updated
    return if GitHub.single_business_environment?
    return unless @org_selection_type_changed
    @org_selection_type_changed = T.let(false, T.nilable(T::Boolean))

    TeamOrchestration.org_selection_type_changed(
      team: self,
      business_id: business_id
    ).execute(synchronous: false)
  end

  sig { params(user_ids: T.nilable(T::Array[Integer])).void }
  def update_buas(user_ids = nil)
    return if GitHub.single_business_environment?
    business = T.must(self.business)
    user_account_ids = business.user_accounts.where(user_id: user_ids || member_ids).pluck(:id)
    business.update_license_usage(user_account_ids: user_account_ids, license_job_delay: LICENSE_JOB_DELAY_SECONDS.seconds)
  end

  sig { params(action: Symbol, operation: Symbol, user_ids: T.nilable(T::Array[Integer])).void }
  def members_or_organizations_updated(action:, operation:, user_ids: nil)
    return if GitHub.single_business_environment?
    update_buas(user_ids)

    if action == :add && (operation == :org || operation == :team)
      GlobalInstrumenter.instrument("business_team.enablement_toggled", {
        consuming_license: true,
        business_team: self,
      })
    elsif operation == :team && action == :remove
      GlobalInstrumenter.instrument("business_team.enablement_toggled", {
        consuming_license: false,
        business_team: self,
      })
    elsif operation == :org && action == :remove && !has_any_orgs?
      GlobalInstrumenter.instrument("business_team.enablement_toggled", {
        consuming_license: false,
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

  sig { params(user_ids: T::Array[Integer]).void }
  def add_member_role(user_ids)
    BusinessUserAccount.add_business_role_to_accounts(:member, T.must(business).user_accounts.where(user_id: user_ids).and(BusinessUserAccount.no_roles([:member]).or(BusinessUserAccount.where(business_roles_bitfield: nil))))
  end

  # Public: Returns the type of team: 'organization' or 'enterprise'.
  sig { override.returns(String) }
  def team_type
    "enterprise"
  end

  sig { override.void }
  def instrument_rename
    if business&.feature_flag_enabled?(:enterprise_teams_audit_logs, default: false)
      instrument :rename,
        name: name,
        name_was: name_before_last_save,
        business_id: business&.id
    end
  end

  sig { override.params(user: User, adder: T.nilable(User), caller_type: T.nilable(Symbol)).void }
  def instrument_add_member(user, adder, caller_type = nil)
    if business&.feature_flag_enabled?(:enterprise_teams_audit_logs, default: false)
      instrument_options = {
        user: user,
        business: business
      }
      instrument_options[:actor] = adder if adder.present?
      instrument :add_member, instrument_options
      GlobalInstrumenter.instrument("team.add_member", instrument_options.merge(
        team: self,
        action: :add,
      ))
    else
      super(user, adder, caller_type)
    end
  end

  sig { override.params(user: User, exclude_audit_log_instrumentation: T.nilable(T::Boolean)).void }
  def instrument_remove_member(user, exclude_audit_log_instrumentation: false)
    if business&.feature_flag_enabled?(:enterprise_teams_audit_logs, default: false)
      unless exclude_audit_log_instrumentation
        instrument :remove_member, user: user, business: business
      end
      GlobalInstrumenter.instrument("team.remove_member", {
        user: user,
        business: business,
        team: self,
        action: :remove,
      })
    else
      super(user, exclude_audit_log_instrumentation: exclude_audit_log_instrumentation)
    end
  end
end
