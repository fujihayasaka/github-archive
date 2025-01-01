# typed: true
# frozen_string_literal: true

class Team < ApplicationRecord::Domain::Users
  extend GitHub::SimplePagination

  include GitHub::BatchedScope

  include Ability::Actor
  include Ability::Subject
  include Ability::Membership

  include Avatar::List::Model
  include GitHub::Relay::GlobalIdentification
  include GitHub::Validations

  include Configurable
  include Configurable::DisableTeamPostCreation

  include Instrumentation::Model
  include LdapMapping::Subject
  include Notifications::SubscribableList
  include PrimaryAvatar::Model
  include Referenceable
  include GitHub::FlipperActor
  include GitHub::VexiActor
  include HydroEventHelper

  include Team::LdapSync
  include Team::LicensedCustomerDependency
  include Team::Permissions
  include Team::Roles
  include Team::Nested
  include Team::NewsiesAdapter
  include LegacyImportable

  include ::Permissions::Attributes::Wrapper
  self.permissions_wrapper_class = ::Permissions::Attributes::Team

  class EmptyOwnersError < StandardError ; end
  class FeatureFlagError < StandardError ; end
  class BulkAddMembersError < StandardError ; end

  TEAM_UPDATE_BATCH_SIZE = 100
  AUTO_SUBSCRIBE_BATCH_SIZE = 100
  DEFAULT_PERMISSION = "pull"
  # Internal: Lookup table mapping team permissions to abilities
  PERMISSIONS_TO_ABILITIES = {
    "admin" => :admin,
    "push"  => :write,
    "pull"  => :read,
    "triage" => :triage,
    "maintain" => :maintain,
  }
  ABILITIES_TO_PERMISSIONS = PERMISSIONS_TO_ABILITIES.invert.with_indifferent_access
  PERMISSIONS = PERMISSIONS_TO_ABILITIES.keys
  ABILITIES = ABILITIES_TO_PERMISSIONS.keys
  # Internal: is a team eligible to become a child of another? "ELIGIBLE" means
  # yes and all others mean no for differenct reasons.
  ELIGIBLITY_STATUSES = {
    secret: "SECRET",
    ancestor: "ANCESTOR",
    child: "CHILD",
    eligible: "ELIGIBLE",
    permission: "PERMISSION",
  }
  REPOSITORY_QUERY_BATCH_SIZE = 1000
  NOTIFICATIONS_DISABLED = "notifications_disabled"
  NOTIFICATIONS_ENABLED = "notifications_enabled"

  enum :privacy, { secret: 0, closed: 1 }
  enum :notification_setting, { notifications_enabled: 0, notifications_disabled: 1 }

  include Team::ExternalIdentityDependency
  include Team::RoleBasedPermissionsDependency
  include Team::UserRankedDependency
  include Team::UserStatusDependency
  include Team::MemexDependency
  include Team::SizeDependency

  attr_reader :old_team
  attr_accessor :eligibility_status

  default_scope { where.not(organization_id: nil) if GitHub.flipper[:team_default_scope].enabled? }

  scope :owned_by, -> (org) { where(organization_id: Array(org).map(&:id)) }
  scope :excluding_organization_ids, -> (ids) {
    ids.any? ? where("teams.organization_id NOT IN (?)", ids) : scoped
  }

  scope :with_minimum_privacy, lambda { |privacy|
    where(arel_table[:privacy].gteq(privacies[privacy]))
  }

  scope :legacy_admin, -> { where(permission: "admin").where("name <> 'Owners'") }

  scope :not_externally_managed, -> {
    where(<<-SQL)
      NOT EXISTS (
        SELECT 1 FROM external_group_teams AS egt
        WHERE egt.team_id = teams.id
        LIMIT 1
      )
    SQL
  }

  scope :like_name, -> (input) {
    where("name LIKE ?", "%#{input}%")
  }

  scope :order_by_name_asc, -> {
    order("name ASC")
  }

  scope :with_no_parent, -> {
    where("tree_path NOT LIKE '%/%'")
  }

  belongs_to :organization, class_name: "Organization"
  belongs_to :creator, class_name: "User"

  has_many :team_invitations

  has_one :enterprise_team_organization_mapping, foreign_key: :team_id, inverse_of: :team

  has_many :team_pending_invitations,
    -> { where(OrganizationInvitation.pending.where_values_hash) },
    through: :team_invitations,
    source: :organization_invitation

  has_many :team_membership_requests
  private :team_membership_requests

  has_many :pending_team_membership_requests,
    -> { where(approved_at: nil) },
    class_name: "TeamMembershipRequest"

  has_many :discussion_posts

  # rubocop:todo Rails/InverseOf
  has_many :requests_to_parent, class_name: "TeamChangeParentRequest", foreign_key: :parent_team_id, dependent: :destroy
  has_many :requests_to_be_child, class_name: "TeamChangeParentRequest", foreign_key: :child_team_id, dependent: :destroy
  # rubocop:enable Rails/InverseOf

  has_many :review_request_delegation_excluded_members, dependent: :destroy

  has_many :user_roles, as: :actor, dependent: :destroy

  has_many :group_mappings, class_name: "Team::GroupMapping"

  has_one :dashboard, class_name: "TeamDashboard", dependent: :destroy
  has_many :user_dashboard_teams, class_name: "UserDashboardTeam", dependent: :destroy
  has_many :pinned_dashboards, class_name: "TeamDashboard", through: :user_dashboard_teams, source: :user_dashboard, disable_joins: true

  # We are not using MemexProjectLink for teams and instead are leveraging the existing logic that we use when adding a team to the project.
  # We get all UserRoles where the current team has any role for a MemexProject, then we get the IDs of these projects and then we get the respective MemexProjects.
  def memex_projects
    team_roles = UserRole.where(
      actor_type: "Team",
      actor_id: id,
      target_type: "MemexProject"
    )

    id_list_for_memex_projects = team_roles.pluck(:target_id)

    MemexProject.where(id: id_list_for_memex_projects)
  end

  has_one :external_group_team, dependent: :destroy

  # Repository association for the repository that this team's posts were migrated to
  belongs_to :repository

  validates_presence_of :name
  validates_presence_of :organization_id, unless: :business_team?

  validates :name, unicode3: true
  validates :name, length: { maximum: 255 }
  validates_inclusion_of :permission, in: PERMISSIONS
  validate :name_and_slug_uniqueness_by_org
  validate :validate_parent_team_is_in_org, :validate_parent_team_does_not_cause_cycle, :validate_parent_not_secret, :validate_secret_or_nested, :validate_parent_has_no_group_mappings, :validate_parent_is_not_enterprise_team_managed

  validates :review_request_delegation_member_count, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: Team::ReviewRequestDelegation::DELEGATE_LIMIT }
  enum :review_request_delegation_algorithm, { round_robin: 0, load_balance: 1 }, scopes: false

  before_validation :strip_name
  before_validation :set_slug, unless: :importing?
  before_validation :restrict_changes_to_owners_team
  before_validation :set_default_permission

  after_commit :instrument_creation, on: :create
  after_create :add_team_as_org_dependent, unless: :business_team?

  after_commit :instrument_update, on: :update

  after_update :update_repository_grants, if: :saved_change_to_permission?
  after_update_commit :instrument_change_privacy, if: :saved_change_to_privacy?
  after_update_commit :instrument_rename, if: :saved_change_to_name?

  after_initialize :reset_parent_team
  after_save :update_tree_path

  # The transaction around Platform::Mutations::UpdateTeam causes that the job is enqueued
  # and sometimes dispatched before the transaction finishes. When this happens, the job can't
  # see the data modified in the unicorn process, thus not being able to apply the team change.
  # For that reason, we moved enqueueing the job to an after commit hook, until a more general
  # solution, like the one documented at the end of https://github.com/github/github/issues/80642#issuecomment-353127221
  # is implemented. Please also read https://github.slack.com/archives/C103DQUPL/p1513866118000286
  # for more context
  after_commit :enqueue_handle_team_parent_changes, if: :enqueue_handle_team_parent_changes_after_commit

  batch_method(:affiliated_abilities) do |teams, affiliation, order|
    team_ids_by_teams = teams.index_with do |team|
      case affiliation
      when :immediate
        [team.id]
      when :inherited
        team.ancestor_ids
      when :all
        team.id_and_ancestor_ids
      end
    end

    if teams.present? && teams.first&.organization&.feature_enabled?(:refactor_team_affiliated_abilities)
      abilities = Ability
      .select(:actor_id, :subject_id, :priority, :action)
      .where(
        actor_type: "Team",
        actor_id: team_ids_by_teams.values.flatten.uniq,
        subject_type: "Repository",
        priority: Ability.priorities[:direct])
      .order(subject_id: order)
      .to_a
    else
      abilities = Ability
      .where(
        actor_type: "Team",
        actor_id: team_ids_by_teams.values.flatten.uniq,
        subject_type: "Repository",
        priority: Ability.priorities[:direct])
      .order(subject_id: order)
      .to_a
    end
    teams.index_with do |team|
      team_id = team_ids_by_teams[team]
      abilities.select { |ability| team_id.include?(ability.actor_id) }
    end
  end

  def find_or_create_dashboard
    TeamDashboard.retry_on_find_or_create_error do
      dashboard ||
        ActiveRecord::Base.connected_to(role: :writing) { create_dashboard }
    end
  end

  # Public: The list of members who are eligible for a PR review request
  def review_request_team_member_ids
    if review_request_delegation_include_child_team_members
      descendant_or_self_member_ids
    else
      member_ids
    end
  end

  # Public: The total number of team members in this installation (used for
  # enterprise stats).
  def self.total_team_members
    ActiveRecord::Base.connected_to(role: :reading) do
      Ability.connection.select_value(Arel.sql(<<-SQL, direct: Ability.priorities[:direct]))
        SELECT COUNT(1)
        FROM abilities
        WHERE priority   = :direct
        AND actor_type   = 'User'
        AND subject_type = 'Team'
      SQL
    end
  end

  # Public: Given an Array of Team IDs, return all team members as a unique,
  # sorted Array of User IDs. This is a low level method, so try to use methods
  # like Team.members_of(*team_ids) instead.
  def self.user_ids_for(team_ids)
    return [] if team_ids.empty?

    PermissionCache.fetch ["user_ids_for", team_ids] do
      GitHub.instrument "ability.team.user-ids-for" do

        sql_bindings = {
          direct: Ability.priorities[:direct],
          team_ids: team_ids,
        }

        sql = Arel.sql <<-SQL, **sql_bindings
          SELECT actor_id
          FROM   abilities ab
          WHERE  ab.actor_type   = 'User'
          AND    ab.subject_id  IN (:team_ids)
          AND    ab.subject_type = 'Team'
          AND    ab.priority     = :direct
        SQL

        Ability.connection.select_values(sql).uniq.sort!
      end
    end
  end

  # Public: Returns teams that have no members.
  #
  # team_ids = teams to inpsect for members
  #
  # Returns an Team AR Relation.
  def self.without_members(team_ids)
    ActiveRecord::Base.connected_to(role: :reading) do
      sql_bindings = {
        team_ids: team_ids,
        priority: [Ability.priorities[:direct], Ability.priorities[:indirect]],
      }

      sql = Arel.sql <<-SQL, **sql_bindings
        SELECT DISTINCT
          subject_id
        FROM
          abilities
        WHERE
          subject_id IN (:team_ids) AND
          subject_type = 'Team' AND
          priority IN (:priority) AND
          actor_type = 'User'
      SQL

      ids_of_teams_with_members = Ability.connection.select_rows(sql)
      team_ids = team_ids - ids_of_teams_with_members.flatten

      where(id: team_ids)
    end
  end

  # Public: Given a collection of teams, search them by name and slug using the
  # provided query.
  #
  # Returns: ActiveRecord::Relation of Teams.
  def self.search_name_and_slug(query:, scope: ::Team)
    sanitized_query = ActiveRecord::Base.sanitize_sql_like(query.to_s.strip.downcase).presence
    return scope unless sanitized_query

    scope.where(["name LIKE :query OR slug LIKE :query", query: "%#{sanitized_query}%"])
  end

  # By default abilities are cleared when any ActiveRecord class mixes-in Ability::Participant
  # However, we want to take control over the deletion of team hierarchies to do it
  # more performantly and in a sequential process.
  #
  # See #destroy, which is aliased to #destroy_with_descendants_support
  #
  def clear_abilities_per_destroyed_record?
    false
  end

  # Public: Select the attributes for updating a team
  #
  # In our team/creator and team/editor code we pass along attributes from the controller
  # that also includes ldap_dn (for the ldap sync code) and other attributes. Not all
  # attributes passed from the controller will be attributes that the Team Active Record
  # record can accept.
  #
  # To avoid an unknown attribute error, parse out the attributes just for a Team
  # before sending them to Active Record's `build`, `create`, or `update` methods.
  #
  # Returns a hash of attributes
  #
  def self.team_attributes_hash(attrs)
    team_attrs = Set.new self.column_names.map(&:to_s)
    attrs.select do |k, _|
      team_attrs.include?(k.to_s)
    end
  end

  # Public: Destroy this teams and their descendants by removing the descendants first
  #
  # The purpose of this method is to remove in bulk the dependants
  # when the descendants of a team that's being removed, need to be removed as well.
  #
  def destroy
    update_attribute(:deleted, true) unless frozen?
    Destruction::DestroyOperation.new(self).execute
    self.freeze
  end

  # Defines an active record scope for use in the members connection.
  # A distinct scope is implicitly added to this method. This is because users
  # can be a part of descendant teams and appear multiple times.
  #
  # Returns an active record scope for the team members
  def members_scope(membership: :all, action: nil)
    case membership
    when :immediate
      members(action: action).distinct # distinct scope added here to maintain parity other methods
    when :child_team
      descendant_members(action: action)
    when :all
      descendant_or_self_members(action: action)
    end
  end

  def members_scope_count(membership: :all, action: nil)
    case membership
    when :immediate
      members_count(action: action)
    when :child_team
      descendant_members_count(action: action)
    when :all
      descendant_or_self_members_count(action: action)
    end
  end

  # Returns an active record scope for the repositories with the given affiliation
  # Be careful: like Team#repositories, if you are presenting a list of
  # repositories to someone, don't use this method.
  # Use the GraphQL team repository connection instead.
  #
  # affiliation:
  #  immediate - the repositories that the team has a direct ability for
  #  inherited - the repositories that the team has inherited abilities for
  #  all - the repositories that the team or its ancestors have a direct ability for
  def repositories_scope(affiliation: :all)
    repo_ids = direct_or_inherited_repo_ids(affiliation: affiliation)
    T.must(organization).repositories.where(id: repo_ids)
  end

  # Returns an active record scope for the repositories with the given affiliation across many teams
  # Teams must belong to the same organization
  # Be careful: like Team#repositories, if you are presenting a list of
  # repositories to someone, don't use this method.
  # Use the GraphQL team repository connection instead.
  #
  # teams: a list of Team objects. Must all belong to the same organization
  #
  # affiliation:
  #  immediate - the repositories that the team has a direct ability for
  #  inherited - the repositories that the team has inherited abilities for
  #  all - the repositories that the team or its ancestors have a direct ability for
  def self.repositories_scope(teams:, affiliation: :all)
    organization = teams.first.organization
    raise ArgumentError, "All teams must belong to the same organization" unless teams.all? { |t| t.organization_id == organization.id }
    repo_ids = direct_or_inherited_repo_ids(teams: teams, affiliation: affiliation)
    organization.repositories.where(id: repo_ids)
  end

  # Returns the unique count of repositories with the given affiliation
  #
  # affiliation:
  #  immediate - the repositories that the team has a direct ability for
  #  inherited - the repositories that the team has inherited abilities for
  #  all - the repositories that the team or its ancestors have a direct ability for
  def repositories_scope_count(affiliation: :all)
    ability_repo_ids = direct_or_inherited_repo_ids(affiliation: affiliation)
    org_repo_ids = T.must(organization).repositories.pluck(Arel.sql("/*vt+ IGNORE_MAX_MEMORY_ROWS=1 */ id"))
    (ability_repo_ids & org_repo_ids).size
  end

  # Returns a list of repo ids with the given affiliation
  # Be careful: like Team#repositories, if you are presenting a list of
  # repositories to someone, don't use this method.
  # Use the GraphQL team repository connection instead.
  #
  # affiliation:
  #  immediate - the repo ids that the team has a direct ability for
  #  inherited - the repo ids that the team has inherited abilities for
  #  all - the repo ids that the team or its ancestors have a direct ability for
  # sort: sort to apply. note: sort is on abilities table so only fields on
  #  the abilities table are available. ex { action: :desc }
  # action - the permission this team should have on the repositories.
  #          Valid values are :read, :write, or :admin. Default: [] which indicates any.
  #
  # Returns a [repo Id]
  def direct_or_inherited_repo_ids(affiliation: :all, sort: {}, action: [])
    Team.direct_or_inherited_repo_ids(teams: [self], affiliation: affiliation, sort: sort, action: action)
  end

  # Returns a list of repo ids with the given affiliation across many teams
  # All teams must belong to the same repositories
  # Be careful: like Team#repositories, if you are presenting a list of
  # repositories to someone, don't use this method.
  # Use the GraphQL team repository connection instead.
  #
  # teams: a list of Team objects. Must all belong to the same organization
  #
  # affiliation:
  #  immediate - the repo ids that the team has a direct ability for
  #  inherited - the repo ids that the team has inherited abilities for
  #  all - the repo ids that the team or its ancestors have a direct ability for
  # sort: sort to apply. note: sort is on abilities table so only fields on
  #  the abilities table are available. ex { action: :desc }
  # action - the permission this team should have on the repositories.
  #          Valid values are :read, :write, or :admin. Default: [] which indicates any.
  #
  # Returns a [repo Id]
  def self.direct_or_inherited_repo_ids(teams:, affiliation: :all, sort: {}, action: [])
    organization_id = teams.first.organization_id
    raise ArgumentError, "All teams must belong to the same organization" unless teams.all? { |t| t.organization_id == organization_id }

    team_ids = teams.flat_map do |team|
      case affiliation
      when :immediate then team.id
      when :inherited then team.ancestor_ids
      when :all then team.id_and_ancestor_ids
      end
    end

    qry = Ability.where(
      actor_type: "Team",
      actor_id: team_ids,
      subject_type: "Repository",
      priority: Ability.priorities[:direct],
    )

    # avoid unnecessarily expensive IN query if we are querying for all abilities.
    qry = qry.where(action: action) unless action.empty?
    qry = qry.order(sort) unless sort.empty?

    qry.pluck(:subject_id)
  end

  # Fetch the User IDs for the list of Team IDs.
  #
  # Returns a Hash{team_id Integer => Array[user_id Integer...]}.
  def self.member_ids_indexed_by_team_ids(team_ids)
    results = Hash.new { |h, k| h[k] = [] }

    ActiveRecord::Base.connected_to(role: :reading) do
      Ability.where(
        subject_id: team_ids,
        subject_type: "Team",
        actor_type: "User",
        priority: Ability.priorities[:direct]
      ).distinct
      .pluck(:actor_id, :subject_id).each do |member_id, team_id|
        results[team_id] << member_id
      end
    end

    results
  end

  def self.valid_privacy?(privacy)
    privacies[privacy].present?
  end

  def self.valid_notification_setting?(notification_setting)
    notification_settings[notification_setting].present?
  end

  # The class name persisted as `target_type` when a UserRole is created
  # with this object as target.
  #
  # Returns: String
  def self.user_role_target_type
    "Team"
  end

  # Public: Override Ability::Participant#ability_description, building a
  # string that looks like a team mention.
  def ability_description
    "@#{T.must(organization).login}/#{name}"
  end

  # Public: Returns either the User who created the team, or the Organization that the team
  # belongs to.
  #
  # This method is mostly going to be used for front-end display purposes.
  def creator
    super || organization
  end

  # Public: Find a single team given owning Org name and a slug
  #
  # org_name - String name of the owning organization
  # slug - String slug that corresponds to the Team
  #
  # Returns the found Team or nil if none was found
  def self.with_org_name_and_slug(org_name, slug)
    joins(:organization).readonly(false).
      where("users.login" => org_name).
      where("teams.slug" => slug).
      first
  end

  # Find a team by its String combined slug, e.g. "github/web"
  #
  # combined_slug - String slug to search for
  #
  # Returns the found Team or nil if none was found
  def self.find_by_combined_slug(combined_slug) # rubocop:disable GitHub/FindByDef
    if combined_slug.include? "/"
      with_org_name_and_slug *combined_slug.split("/")
    else
      raise ArgumentError, "expected `#{combined_slug}' to include `/'"
    end
  end

  # Workaround for "incompatible character encodings: UTF-8 and ASCII-8BIT"
  # exception.
  def description
    return unless description = super
    if description.respond_to?(:force_encoding)
      description = description.dup.force_encoding("UTF-8")
      description = GitHub::Encoding.transcode(description, "UTF-8", "UTF-8") unless description.valid_encoding?
    end
    description
  end

  # Public: Returns a uniquely identifiable slug for an Org / Team combination
  #
  # Examples:
  #
  #  team.combined_slug
  #  # => 'github/enterprise'
  #  team.combined_slug
  #  # => 'github/core-backend-devs'
  #
  # Returns the slug
  def combined_slug
    "#{T.must(organization).display_login}/#{slug}"
  end
  alias_method :to_s, :combined_slug

  # Public: Use the teams's slug for URL generation
  def to_param
    slug
  end

  # Absolute permalink URL for this team.
  #
  # include_host - Turn off the `GitHub.url` host in the url. (default true)
  #                team.permalink(include_host: false) => `/orgs/github/teams/employees`
  #
  def permalink(include_host: true)
    endpoint = "/orgs/#{T.must(organization).display_login}/teams/#{to_param}"

    if include_host
      "#{GitHub.url}#{endpoint}"
    else
      endpoint
    end
  end

  # Internal: Set a slug based on the Team's name.
  # Will set a unique slug scoped with the Organization, to avoid clashes
  # between two teams with names like "ruby team" and "ruby-team".
  # This will set the slug if the name of the Team changes
  # or if the slug is nil (to handle legacy data).
  #
  # Returns the slug that was set, or nil if slug was not set
  def set_slug
    return unless name_changed? || slug.nil?
    self.slug = generate_unique_slug
  end

  # Internal: generate unique slug for Org / Team combination
  def generate_unique_slug
    candidate = base = T.must(self.name).parameterize.to_s

    if candidate.blank?
      candidate = base = "team"
    end

    index = 0
    while any_conflicting_slugs?(candidate)
      index += 1
      candidate = "#{base}-#{index}"
    end
    candidate
  end

  # Internal: Find conflicting slugs
  # Ignoring the current slug if the current Team exists
  #
  # Returns the count of conflicting slugs found
  def any_conflicting_slugs?(candidate)
    scope = self.class.where(organization_id: organization_id, slug: candidate)
    scope = scope.where("id <> ?", id) unless new_record?
    scope.any?
  end

  # Public: the repositories associated with this team that are visible to the
  # specified user.
  #
  # Note: it's possible that the specified user isn't able to see this team, but
  # is able to see some of the repos on this team (because they're public, or
  # because they're on another team). This method will still return those repos,
  # so make sure to check separately that the user is able to see this team.
  #
  # user - The user to check repository visibility for.
  #
  # Returns an ActiveRecord scope.
  def visible_repositories_for(user, affiliation: :immediate)
    repo_ids = direct_or_inherited_repo_ids(affiliation: affiliation)

    return repositories.none if repo_ids.empty?

    if GitHub.enterprise? && user&.site_admin?
      return T.must(organization).repositories.where(id: repo_ids)
    end

    associated_repository_ids = user&.associated_repository_ids(repository_ids: repo_ids)
    organization&.visible_repositories_for(user, associated_repository_ids: associated_repository_ids).where(id: repo_ids)
  end

  # Public: like visible_repositories_for but results can be sorted by the fields
  # defined in Platform::Enums::TeamRepositoryOrderField
  #
  # user - The user to check repository visibility for.
  # sort - A hash representing the order field and direction.
  #
  # Returns an ActiveRecord scope.
  def sorted_visible_repositories_for(user, affiliation: :immediate, sort: {})
    order_field, order_direction = validate_repositories_sorting_arguments(sort: sort)

    # Since "action" is a column on Abilities, the order must be applied when
    # querying for the repo ids through Authorization::Service#subject_ids_for_multiple_actors
    # ex: { action: :desc }
    repo_ids_sort = order_field == "action" ? { action: order_direction.downcase.to_sym, subject_id: order_direction.downcase.to_sym } : {}
    repo_ids = direct_or_inherited_repo_ids(affiliation: affiliation, sort: repo_ids_sort)

    return repositories.none if repo_ids.empty?

    if GitHub.enterprise? && user&.site_admin?
      scope = T.must(organization).repositories.where(id: repo_ids)
    elsif ProgrammaticActor::RepositoryFilter.applicable?(user)
      accessible_repository_ids = ProgrammaticActor::RepositoryFilter.perform(actor: user, repository_ids: repo_ids)

      scope = Repository.where(id: accessible_repository_ids).or(Repository.public_scope.where(owner_id: organization_id, active: true, id: repo_ids))
    else
      associated_repository_ids = user&.associated_repository_ids(repository_ids: repo_ids)

      visible_repository_scope = organization&.visible_repositories_for(user, associated_repository_ids: associated_repository_ids)

      if visible_repository_scope.where_values_hash.key?("id")
        ids_from_where_clause = visible_repository_scope.where_values_hash["id"]
        ids_from_where_clause = [ids_from_where_clause] unless ids_from_where_clause.is_a?(Array)
        repo_ids &= ids_from_where_clause
      end

      scope = visible_repository_scope.rewhere(id: repo_ids)
    end

    add_order_to(scope, field: order_field, direction: order_direction, repo_ids:)
  end

  def add_order_to(scope, field:, direction:, repo_ids:)
    if field.present?
      if field == "action"
        # preserves the order of the repositories when the field is "action"
        scope = scope.order(Arel.sql("FIELD(repositories.id, #{repo_ids.join(",")})")).
          order("repositories.id")
      else
        # orders the repositories for all other fields
        scope = scope.order("repositories.#{field} #{direction}")
      end
    end

    scope
  end

  # Validates the sorting arguments for repositories.
  # order direction can be one of ascending ("ASC") or descending ("DESC")
  # order field can be any field defined by Platform::Enums::TeamRepositoryOrderField
  #
  # sort -- A hash representing the order field and direction.
  #
  # Returns an Array with valid field and direction or nil.
  private def validate_repositories_sorting_arguments(sort: {})
    order_field, order_direction = sort.values_at(:field, :direction)

    valid_order_field = Platform::Enums::TeamRepositoryOrderField.values.any? { |_, v| v.value == order_field }
    valid_order_direction = Platform::Enums::OrderDirection.values.any? { |_, v| v.value == order_direction }

    [order_field, order_direction] if valid_order_field && valid_order_direction
  end

  # Public: the most capable inherited ability a team has for a repository.
  # Inherited ability means an ability inherited from a parent team.
  #
  # repo - The repo to check abilities for
  #
  # Returns an Ability or nil.
  def most_capable_inherited_ability_for_repo(repo)
    return nil unless self.ancestor_ids.present?
    Ability.where(
      actor_id: self.ancestor_ids,
      actor_type: "Team",
      subject_id: [repo.id],
      subject_type: "Repository",
      priority: Ability.priorities[:direct],
    ).max
  end

  # Public: the most capable ability a team has for the given subjects.
  # abilities w/ team as the actor are always :direct
  #
  # subject_ids - The ids of the subjects to check abilities for
  # subject_type - The type of the subject
  #
  # Returns a Hash{subject Id => Ability}.
  def most_capable_abilities_on_subjects(subject_ids, subject_type:)
    abilities = Ability.where(
      actor_id: id_and_ancestor_ids,
      actor_type: "Team",
      subject_type: subject_type.to_s,
      subject_id: subject_ids,
      priority: Ability.priorities[:direct],
    )

    select_most_capable_ability_for_subject(abilities)
  end

  # Internal: Selects the most capable abilities for each subject ignoring
  # which team the permission came from. However, we prefer the team's
  # own ability record over an ancestor team's record if there is a tie
  # in permission level.
  #
  # abilities - [Ability]
  #
  # Returns a Hash{subject Id => Ability}.
  private def select_most_capable_ability_for_subject(abilities)
    abilities.each_with_object({}) do |ability, result|
      subject_id = ability.subject_id
      actor_id = ability.actor_id

      if most_capable = result[subject_id]
        if ability > most_capable
          result[subject_id] = ability
        elsif ability == most_capable && actor_id == id
          result[subject_id] = ability
        end
      else
        result[subject_id] = ability
      end
    end
  end

  # Public: checks if the team has a direct ability on a repository as opposed
  # to inherited from an ancestor team
  #
  # repo - The repo to check
  #
  # Returns boolean
  def has_repository?(repo)
    !!Authorization.service.direct_ability_between(actor: self, subject: repo)
  end

  # Public: the repositories associated with this team.
  #
  # Be careful: If you are presenting a list of repositories to someone, don't
  # use this method. Use #visible_repositories_for instead.
  #
  # Returns an ActiveRecord scope.
  def repositories
    Repository.where(id: repository_ids)
  end

  # Public: the repositories associated with this team queried in batches.
  #
  # Be careful: If you are presenting a list of repositories to someone, don't
  # use this method. Use #visible_repositories_for instead.
  #
  # Returns an Array of Repository.
  def batched_repositories
    Repository.batched_scope(:id, values: repository_ids, batch_size: REPOSITORY_QUERY_BATCH_SIZE).to_a
  end

  # Public: the Repository ids this team is directly granted read/write/admin access to
  # does not include all org repos when all org members get access
  # or when team is granted an all repo role
  def repository_ids
    GitHub.instrument "ability.team.repository-ids" do
      Ability.where(
        subject_type: "Repository",
        actor_id: id,
        actor_type: "Team",
        priority: Ability.priorities[:direct],
      ).pluck(:subject_id)
    end
  end

  # Public: the projects associated with this team that are visible to the
  # specified user.
  #
  # Note: it's possible that the specified user isn't able to see this team, but
  # is able to see some of the projects on this team (because they're public,
  # or because they're on another team). This method will still return those
  # projects, so make sure to check separately that the user is able to see
  # this team.
  #
  # user - The user to check project visibility for.
  # affiliation:
  #  immediate - Get projects that the team has a direct ability for
  #  inherited - Get projects that the team has inherited abilities for
  #  all - Get projects that the team or its ancestors have a direct ability
  #
  # Returns an ActiveRecord scope.
  def visible_projects_for(user, affiliation: :immediate)
    project_ids = direct_or_inherited_project_ids(affiliation: affiliation)

    return Project.none if project_ids.empty?

    T.must(organization).visible_projects_for(user).where(id: project_ids)
  end

  # Public: the projects associated with this team.
  #
  # Be careful: If you are presenting a list of projects to someone, don't use
  # this method. Use visible_projects_for instead.
  #
  # Returns an ActiveRecord scope.
  def projects
    subject_ids = Ability.where(
      subject_type: "Project",
      actor_id: id,
      actor_type: self.ability_type,
      priority: Ability.priorities[:direct],
    ).pluck(:subject_id)
    Project.where(id: subject_ids)
  end

  # Returns a list of project ids with the given affiliation
  # Be careful: like Team#projects, if you are presenting a list of
  # projects to someone, don't use this method.
  # Use the GraphQL team projects connection instead.
  #
  # affiliation:
  #  immediate - the project ids that the team has a direct ability for
  #  inherited - the project ids that the team has inherited abilities for
  #  all - the project ids that the team or its ancestors have a direct ability
  # for
  #
  # Returns a [project Id]
  def direct_or_inherited_project_ids(affiliation: :all)
    team_ids = case affiliation
    when :immediate then id
    when :inherited then ancestor_ids
    when :all then id_and_ancestor_ids
    end

    Ability.where(
      actor_id: team_ids,
      actor_type: "Team",
      subject_type: "Project",
      priority: Ability.priorities[:direct],
    ).pluck(:subject_id)
  end

  # Public: Whether this team is updatable by a given actor
  #
  # Returns a boolean
  def updatable_by?(actor)
    (actor.can_have_granular_permissions? && T.must(organization).resources.members.writable_by?(actor)) || adminable_by?(actor)
  end

  def async_updatable_by?(actor)
    promises = [async_adminable_by?(actor)]
    promises.append(T.must(organization).resources.members.async_writable_by?(actor)) if actor.can_have_granular_permissions?
    Promise.all(promises).then do |results|
      results[0] || results[1]
    end
  end

  # Does this team grant pull access? Because pull is the lowest
  # access level, the answer is always yes.
  def pull?
    true
  end

  # Does this team exist specifically to grant pull access? Any other
  # access level returns false.
  def pull_only?
    permission.blank? || permission == "pull"
  end

  # Does this team grant push access? Pull access is implied.
  def push?
    admin? || push_only?
  end

  # Does this team exist specifically to grant push access? Any other
  # access level returns false.
  def push_only?
    permission == "push"
  end

  # Does this team grant admin access? Push and pull access is
  # implied.
  def admin?
    permission == "admin"
  end

  # Check if this was an admin team in the legacy permission model.
  # This permission still applies for admin teams that were created under
  # the old model and have not been converted to the new model by an org admin.
  # See https://github.com/github/github/pull/45134 for more info
  def legacy_admin?
    permission == "admin" && !legacy_owners?
  end

  # Check if the permission exists and is grantable by the team's owner.
  #
  # Returns
  # * [permission, :success] If the permission exists and is grantable by the
  #     team's owner
  # * [nil, :not_found] If thie permission does not exist
  # * [nil, :forbidden] If the team's owner does not have the appropriate
  #     billing plan to grant the permission
  def fetch_permission(permission)
    perm = PERMISSIONS_TO_ABILITIES[permission]
    return [perm, :success] if %w(read write admin).include? perm.to_s

    # If perm is still nil, it's not read, triage, write, maintain, or admin.
    # Therefore we know permission must be a custom role.
    if perm.nil?
      perm = RepositoryRole.custom_role_by_name(permission, owner: owner)&.name
    end

    return [nil, :not_found] if perm.nil?
    return [nil, :forbidden] unless owner.plan_supports?(:fine_grained_permissions)
    [perm, :success]
  end

  # Convert a legacy admin team to a "modern" team.
  #
  # Returns nothing.
  def migrate_legacy_admin
    if legacy_admin?
      self.permission = "pull"
      save!
    end
  end

  # Is this the team of owners?
  def owners?
    name == "Owners" || name_was == "Owners"
  end

  # Check if this was once the owners team when legacy org membership was around.
  def legacy_owners?
    (name == "Owners" || name_was == "Owners") && permission == "admin"
  end

  # Check if the adder can add a user to the team without needing to first send
  # an invite.
  def can_add_member_without_invite?(user)
    GitHub.bypass_org_invites_enabled? ||
      organization&.enterprise_managed_user_enabled? ||
      organization&.direct_or_team_member?(user) ||
      (organization&.business&.direct_or_team_member?(user) &&
        organization&.meets_sso_requirements?(user: user))
  end

  # Public: Check if the adder can add a user to this team
  #
  # Returns a boolean
  def user_can_add_member?(member, actor:)
    unless organization&.direct_member?(member)
      return actor.can_add_members_for?(organization, teams: [self])
    end

    if actor.can_have_granular_permissions?
      T.must(organization).resources.members.writable_by?(actor)
    else
      adminable_by?(actor)
    end
  end

  # Public: Check if the adder can add users to this team. This check on
  # can_add_members_for will only be executed when when there are ids passed in.
  # The methods assumes that the check if the user ids are members id done outside
  # of this method.
  #
  # Returns a boolean
  def actor_can_add_members?(new_member_ids, actor:)
    return false unless actor
    return actor.can_add_members_for?(organization, teams: [self]) if new_member_ids.any?

    if actor.can_have_granular_permissions?
      T.must(organization).resources.members.writable_by?(actor)
    else
      adminable_by?(actor)
    end
  end

  # Public: Add an array of users to this team.  Each entry in the array will be validated.
  # The method will failover to a single mode when the first error is encountered in a batch. An
  # Array of AddMemberStatus Errors will be returned for each user.
  #
  # users - An array of users to add to the team
  # options - A hash of options
  #   :adder - The user that is adding the user to the team
  #   :skip_organization_seat_checks - A boolean indicating if the organization seat checks should be skipped
  #   :force_emu - A boolean indicating if the enterprise managed user checks should be skipped
  #   :limit - A limit on the number of users to add to the team
  #   :send_notification - A boolean indicating if the user should be sent a notification
  #   :skip_user_synchronize_index - A boolean indicating whether to skip synchronize_search_index calls
  #
  # Returns an array of AddMemberStatus
  def bulk_add_members_with_failover(users, options = {})
    begin
      result = bulk_add_members(users, options)
      raise BulkAddMembersError if result.should_failover?
      users.map { |_| result }
    rescue BulkAddMembersError, GrantPermissionError
      # switch to running in single mode
      # try adding users one by one
      available_seats = ActiveRecord::Base.connected_to(role: :reading) { T.must(organization).business&.available_invitable_licenses } || 0
      seats_used = 0
      out_of_seats = T.let(false, T::Boolean)
      result = users.map do |user|
        begin
          consumed_seats = ActiveRecord::Base.connected_to(role: :reading) { T.must(organization).business&.additional_licenses_consumed_by(user_ids: [user.id].compact) } || 0
          if seats_used > 0 && out_of_seats && consumed_seats > 0
            Team::AddMemberStatus::NO_SEAT
          else
            result = add_member(user, options.merge(skip_license_usage_update: true))
            next result unless result.success?
            seats_used += consumed_seats
            if T.must(organization).business.present? && seats_used >= available_seats
              T.must(organization).business&.license_usage&.add_consumed_seats(seats_used)
              out_of_seats = true
            end
            result
          end
        rescue GrantPermissionError
          Team::AddMemberStatus::NO_PERMISSION
        end
      end
      T.must(organization).business&.update_license_usage if seats_used > 0
      result
    end
  end

  # Public: Add an array of users to this team.  Each entry in the array will be validated.
  # A single AddMemberStatus will be returned when the first error is encountered.
  #
  # users - An array of users to add to the team
  # options - A hash of options
  #   :adder - The user that is adding the user to the team
  #   :skip_license_usage_update - A boolean indicating whether to skip the license usage update
  #   becasue it will be triggered elsewhere
  #   :skip_organization_seat_checks - A boolean indicating if the organization seat checks should be skipped
  #   :force_emu - A boolean indicating if the enterprise managed user checks should be skipped
  #   :limit - A limit on the number of users to add to the team
  #   :send_notification - A boolean indicating if the user should be sent a notification
  #   :skip_user_synchronize_index - A boolean indicating whether to skip synchronize_search_index calls
  #
  # Returns a AddMemberStatus
  def bulk_add_members(users, options = {})
    # Check if the users is present and is an array
    return AddMemberStatus::NOT_AN_ARRAY if users.nil? || !users.is_a?(Array)

    # remove nils from the array and continue with the batch
    users.compact!
    return AddMemberStatus::NOT_USER if users.empty?

    options.assert_valid_keys(:adder, :skip_license_usage_update, :skip_organization_seat_checks, :force_emu, :limit, :caller_type, :send_notification, :skip_user_synchronize_index, :synchronous_orchestration)
    adder = options[:adder]

    # Teams managed by an ET must be altered through the ET
    caller_type = T.let(options[:caller_type], T.nilable(Symbol))
    return AddMemberStatus::ENTERPRISE_TEAM_MANAGED if caller_type != :enterprise_team && self.enterprise_team_managed?

    # Trade Restricted orgs cannot manage their teams
    return AddMemberStatus::TRADE_CONTROLS_RESTRICTED if T.must(organization).has_full_trade_restrictions?

    # Get all direct members of the organization
    user_ids = users.map(&:id).sort
    direct_member_ids = organization&.member_ids(actor_ids: user_ids).sort

    # members that need to be added to the organization
    new_member_ids = user_ids - direct_member_ids

    add_members_status = bulk_validate_add_member_users(users, new_member_ids, options)
    return add_members_status if add_members_status

    scim_managed_enterprise = scim_managed_enterprise?

    members_to_add = users.select { |user| new_member_ids.include?(user.id) }
    already_org_members = user_ids - new_member_ids

    begin
      transaction do
        users.each { |user| user.revoke_new_hire_accesses if GitHub.new_staff_precautions? && github_employees_team? }

        if GitHub.flipper["authz_no_bulk_grant_transaction"].enabled?
          bulk_grant(users, :read, grantor: adder, skip_revoke: true)
        else
          Ability.transaction do
            bulk_grant(users, :read, grantor: adder)
          end
        end

        if scim_managed_enterprise
          # user already a member of team's organization so just add the membership entry
          organization&.bulk_add_organization_membership_entry(user_ids: direct_member_ids, team: self, adder: adder, caller_type: caller_type) if direct_member_ids.any?
          # Since adding team members is already behind a feature flag, we can use the new bulk method
          T.must(organization).bulk_add_members(members_to_add, adder: adder, team: self, skip_license_usage_update: options[:skip_license_usage_update], caller_type: caller_type, skip_user_synchronize_index: options[:skip_user_synchronize_index], synchronous_orchestration: options[:synchronous_orchestration])
        elsif caller_type != :enterprise_team
          # regular user flow
          organization&.bulk_add_members(members_to_add, skip_license_usage_update: options[:skip_license_usage_update], caller_type: caller_type, skip_user_synchronize_index: options[:skip_user_synchronize_index], synchronous_orchestration: options[:synchronous_orchestration])
        end

        if requests = pending_team_membership_requests.where(requester_id: user_ids)
          requests.each { |request| request.cancel(actor: adder) } if requests.any?
        end
      end
    rescue ActiveRecord::ActiveRecordError => e
      # If the any transaction fails with ActiveRecord::ActiveRecordError we don't roll back
      # the transactions in Organization#bulk_add_members that adds the org abilities and around bulk_grant.
      Ability.where(actor_id: user_ids, actor_type: "User", subject_id: id, subject_type: "Team").delete_all
      if organization.present?
        # Since the user was just added through team it cannot be an admin so that check is skipped
        Ability.where(actor_id: new_member_ids, actor_type: "User", subject_id: organization&.id, subject_type: "Organization").delete_all
      end

      raise e
    end

    reload # to refresh the team member associations

    # instrument the add member events
    instrument_add_members(users, adder, caller_type)

    if GitHub.flipper[:team_bulk_add_dashboard_deadlock_retry].enabled?(T.must(organization).business)
      retry_on_deadlock do
        DashboardNoticesStore.bulk_add(user_ids, :org_newbie)
      end.rescue do |result|
        Failbot.report(result, operation: :activate_notice, notice_name: :org_newbie, app: "github-user")
        GitHub::Result.error result
      end
    else
      DashboardNoticesStore.bulk_add(user_ids, :org_newbie)
        .rescue do |result|
          Failbot.report(result, operation: :activate_notice, notice_name: :org_newbie, app: "github-user")
          GitHub::Result.error result
        end
    end

    should_auto_subscribe_user = caller_type != :enterprise_team
    users.each do |user|
      user.reset_notices
      auto_subscribe_user user if should_auto_subscribe_user

      if !user.suspended? && adder != user && send_user_added_notifications? && options[:send_notification] != false
        TeamsMailer.team_added(user, self, adder).deliver_later(queue: "team_member_added_emails")
      end
    end

    Contribution.bulk_clear_caches_for_users(users, context: "bulk_add_org_team_members")
    T.must(organization).business&.update_license_usage unless options[:skip_license_usage_update]

    AddMemberStatus::SUCCESS
  rescue ActiveRecord::RecordNotUnique => e
    # This will only happen due to race conditions (e.g. two identical,
    # simultaneous requests), but handle it anyway
    GitHub.logger.info({
      "code.namespace" => self.class.name,
      "code.function" => "add_member",
      "info.message" => "team.bulk_add_members record not unique",
      "gh.team.name" => name,
      "gh.team.id" => id,
      "gh.user_ids" => user_ids&.join(","),
      "gh.direct_member_ids" => direct_member_ids&.join(","),
      "gh.new_member_ids" => new_member_ids&.join(","),
      "gh.backtrace" => T.must(e.backtrace).join("\n"),
    })
    AddMemberStatus::SUCCESS
  ensure
    users.each { |user| user.clear_employee_memo if self.name == "Employees" } if users.is_a?(Array)
  end

  # Public: Add a user to this team.
  #
  # Returns a Team::AddMemberStatus.
  def add_member(user, options = {})
    if GitHub.flipper[:use_team_add_member_bulk_method].enabled?(user)
      return bulk_add_members([user], options)
    end

    options.assert_valid_keys(:adder, :skip_license_usage_update, :skip_organization_seat_checks, :force_emu, :caller_type, :send_notification, :skip_user_synchronize_index, :synchronous_orchestration)
    adder = options[:adder]
    skip_organization_seat_checks = !!options[:skip_organization_seat_checks]

    # Teams managed by an ET must be altered through the ET
    caller_type = T.let(options[:caller_type], T.nilable(Symbol))
    return AddMemberStatus::ENTERPRISE_TEAM_MANAGED if self.enterprise_team_managed? && caller_type != :enterprise_team

    # Trade Restricted orgs cannot manage their teams
    return AddMemberStatus::TRADE_CONTROLS_RESTRICTED if T.must(organization).has_full_trade_restrictions?

    # Only traditional users can belong to teams.
    return AddMemberStatus::NOT_USER unless user&.user?

    # Check if the user is an an EMU that is externally managed
    if !options[:force_emu] &&
      scim_managed_enterprise? &&
      externally_managed?
      # there is only one external identity linked to an EMU user
      identity = user.external_identities.first
      # Prevent adding of a user not linked to an external group
      return AddMemberStatus::BLOCKED if identity && !external_group_team&.member?(identity.id)
    end

    # Don't add a user to an org they have blocked.
    return AddMemberStatus::BLOCKED if user.blocking?(organization)

    # Don't add a user to a team if the actor is blocked by the user
    return AddMemberStatus::BLOCKED if adder&.blocked_by?(user)

    # Don't add a user twice
    return AddMemberStatus::DUPE if member_ids.include?(user.id)

    unless skip_organization_seat_checks
      # Don't add if per seat organization has no seat for the user.
      return AddMemberStatus::NO_SEAT unless T.must(organization).has_seat_for?(user)

      # Don't add if per seat organization has no seat for the user on pending
      # cycle.
      return AddMemberStatus::PENDING_CYCLE_NO_SEAT unless T.must(organization).has_seat_for?(user, pending_cycle: true)
    end

    # Don't add if user doesn't satisfy the 2FA requirements of the Organization
    return AddMemberStatus::NO_2FA unless T.must(organization).two_factor_requirement_met_by?(user)

    # If specifically joining the github/Employees team, don't add if the user has any SMS 2FA
    if github_employees_team? && user.sms_registrations.any? && GitHub.flipper[:github_employees_no_sms_2fa].enabled?
      return AddMemberStatus::GITHUB_EMPLOYEE_NO_SMS_2FA
    end

    # Don't add if user doesn't satisfy the SAML SSO requirement of the Organization
    return AddMemberStatus::NO_SAML_SSO unless T.must(organization).meets_sso_requirements?(user: user)

    if GitHub.bypass_org_invites_enabled? && adder.present?
      return AddMemberStatus::NO_PERMISSION if !user_can_add_member?(user, actor: adder)
    end

    transaction do
      Ability.transaction do
        # Revoke access for new GitHub hires.
        if GitHub.new_staff_precautions? && github_employees_team?
          user.revoke_new_hire_accesses
        end

        grant user, :read, grantor: adder

        # emu flow
        if scim_managed_enterprise?
          # user already a member of team's organization
          if organization&.direct_member?(user)
            organization&.add_organization_membership_entry(user: user, team: self, adder: adder, caller_type: caller_type)
          else
            organization&.add_member(user, adder: adder, team: self, skip_license_usage_update: options[:skip_license_usage_update])
          end
        else
          if caller_type != :enterprise_team
            # regular user flow
            organization&.add_member(user, skip_license_usage_update: options[:skip_license_usage_update])
          end
        end

        if (request = pending_team_membership_requests.where(requester_id: user.id).first)
          request.cancel(actor: adder)
        end
      end
    end

    reload # to refresh the team member associations

    instrument_options = { user: user }

    if adder.present?
      instrument_options[:actor] = adder
    end

    unless EnterpriseTeam.enabled_for_organizations?(business: self.organization&.business) &&
      caller_type == :enterprise_team
      instrument :add_member, instrument_options
    end
    GlobalInstrumenter.instrument("team.add_member", instrument_options.merge(
      team: self,
      action: :add,
    ))

    user.activate_notice :org_newbie
    auto_subscribe_user user

    if !user.suspended? && adder != user && send_user_added_notifications? && options[:send_notification] != false
      TeamsMailer.team_added(user, self, adder).deliver_later(queue: "team_member_added_emails")
    end

    Contribution.clear_caches_for_user(user, context: "add_org_team_member")

    AddMemberStatus::SUCCESS

  rescue ActiveRecord::RecordNotUnique => e
    # This will only happen due to race conditions (e.g. two identical,
    # simultaneous requests), but handle it anyway
    GitHub.logger.info({
      "code.namespace" => self.class.name,
      "code.function" => "add_member",
      "info.message" => "team.add_member record not unique",
      "gh.team.name" => name,
      "gh.team.id" => id,
      "gh.user.id" => user&.id,
      "gh.backtrace" => T.must(e.backtrace).join("\n"),
    })
    AddMemberStatus::SUCCESS
  ensure
    user.clear_employee_memo if self.name == "Employees"
  end

  # Public: Determines whether if the team is part of an emu enabled enterprise
  #
  # Returns boolean
  def enterprise_managed_user_enabled?
    organization&.enterprise_managed_user_enabled?
  end

  # Public: Determines whether if the team is the Organization that belongs to a business managed through SCIM on an enterprise server
  #
  # Returns boolean
  def enterprise_server_scim_enabled?
    organization&.enterprise_server_scim_enabled?
  end

  # Public: Determines if this Organization belongs to a business that has enterprise managed through SCIM
  #
  # Returns boolean
  def scim_managed_enterprise?
    organization&.scim_managed_enterprise?
  end

  def add_or_invite_member(user:, inviter:, email: nil)
    # Try and find user by email if not already found from previous step through
    # login and email is present. This will help avoid sending the user an
    # unnecessary invite that would consume a license temporarily while the
    # invite is pending if they are already a member of the organization or a
    # member of a business that owns the organization.
    user_from_email = User.find_by_email(email) if user.blank? && email.present?

    if user.present? && can_add_member_without_invite?(user)
      result = add_member(user, adder: inviter)
    elsif user_from_email.present? && can_add_member_without_invite?(user_from_email)
      result = add_member(user_from_email, adder: inviter)
    else
      # The user is not a member of the org, therefore invite them to org.
      if T.must(organization).spammy?
        result = AddMemberStatus::ORG_FLAGGED_SPAMMY
      elsif user.present? && !T.must(organization).has_seat_for?(user)
        result = AddMemberStatus::NO_SEAT
      elsif email.present? && !T.must(organization).has_seat_for_email?(email)
        result = AddMemberStatus::NO_SEAT
      elsif user.present? && !T.must(organization).has_seat_for?(user, pending_cycle: true)
        result = AddMemberStatus::PENDING_CYCLE_NO_SEAT
      elsif email.present? && !T.must(organization).has_seat_for_email?(email, pending_cycle: true)
        result = AddMemberStatus::PENDING_CYCLE_NO_SEAT
      elsif T.must(organization).feature_enabled?(:team_member_rate_limit_fix) && T.must(organization).invitation_rate_limit_exceeded?
        result = AddMemberStatus::RATE_LIMIT_EXCEEDED
      else
        role = :direct_member

        begin
          result = organization&.invite(user, email: email, inviter: inviter, role: role, teams: [self], invitation_source: :member)
        rescue OrganizationInvitation::InvalidError
          # We don't have to be friendly here, since you need to hack around
          # the UI to try to send an invalid invitation.
          result = false
        rescue OrganizationInvitation::TradeControlsError
          result = AddMemberStatus::TRADE_CONTROLS_RESTRICTED
        end
      end
    end

    result
  end

  # Internal: Used by Abilities to ensure that only Users can be granted
  # abilities on a Team.
  def grant?(actor, action)
    actor.is_a?(User) && actor.user? && super
  end

  # currently, there are no constraints to grant a permission over a team over any target
  def can_be_granted_permission_over!(subject, action); end

  # Is this the @github/employees team?
  #
  # Returns boolean.
  def github_employees_team?
    self == GitHub::FeatureFlag.employees_team
  end

  # Public: Add a Repository to this team directly, with admin permissions, and
  # without subscriptions or logging. Used internally as part of the owners team
  # to direct org membership migration.
  #
  # repo - the Repository to add.
  #
  # Returns nothing.
  def add_repository_directly(repo)
    repo.add_team self, action: :admin
  rescue ActiveRecord::RecordNotUnique
    # it's fine.
  end

  # Public: Add a Repository to this team.
  #
  # repo                  - the Repository to add.
  # perm                  - the permission this repo should be added with. Option is
  #                         ignored if the direct org membership flag is not enabled.
  #                         Valid values are :pull, :push, or :admin
  # allow_different_owner - true if explicitly assigning to a team of a new org
  #
  # Returns an ModifyRepositoryStatus.
  def add_repository(repo, perm, allow_different_owner: false, repo_ids: repository_ids)
    # Only permit org-owned repos
    org_id = organization_id
    if !allow_different_owner && repo.organization_id != org_id
      return ModifyRepositoryStatus::NOT_OWNED
    end

    # Advisory temporary private fork access must be managed through its advisory
    return ModifyRepositoryStatus::ADVISORY_WORKSPACE if repo.advisory_workspace?

    # Owners team owns every repo so just ignore it.
    return ModifyRepositoryStatus::OWNERS if legacy_owners?

    # Don't add a repo twice to the same team.
    return ModifyRepositoryStatus::DUPE if repo_ids.include?(repo.id)

    return ModifyRepositoryStatus::GROUP_SETTINGS if repo&.access_group_setting&.deny_team_changes?

    # input action can be in permission or ability format
    repo_permission_role = RepositoryRole.by_name(perm: perm, org: repo.owner)

    # Complain about missing perm when direct org membership is enabled
    if repo_permission_role.nil?
      return ModifyRepositoryStatus::NO_PERMISSION
    end

    # Do it.
    ActiveRecord::Base.connected_to(role: :writing) do
      Ability.transaction do
        repo.add_team self, action: repo_permission_role.name
      end
    end

    instrument :add_repository, \
      repo: repo,
      permission: repo_permission_role.name

    #simple check to reduce useless jobs. Real check is `fork_inherits_teams?`.
    if repo.private?
      add_forks_of(repo)
    end

    if repo.pushable_by?(self)
      GitHub.newsies.async_subscribe_users_to_repository(repo.id, members.map(&:id))
    end

    ModifyRepositoryStatus::SUCCESS

  rescue ActiveRecord::RecordNotUnique
    # Race conditions only, but handle it anyway
    ModifyRepositoryStatus::SUCCESS
  end

  # Public: remove multiple users from the team.
  #
  # users  - the users to be removed.
  # force - skip the expensive membership check and cache refresh, used in batch
  #         operations when removing many users at once.
  # send_notification - whether to notify the user they've been removed
  # team_destroyed - whether or not the user is being removed as part of the
  #                  team being destroyed.
  #
  # Returns nothing
  sig do params(
    users: T.any(ActiveRecord::Relation, T::Array[User]),
    force: T::Boolean,
    send_notification: T::Boolean,
    team_destroyed: T::Boolean,
    queue_delete_jobs: T::Boolean,
    caller_type: T.nilable(Symbol)).void
  end
  def bulk_remove_members(users:, force: false, send_notification: true, team_destroyed: false, queue_delete_jobs: true, caller_type: nil)
    return unless EnterpriseTeam.enabled_for_organizations?(business: self.organization&.business)
    return if users.empty?
    return if !force && !team_destroyed && caller_type != :enterprise_team && self.enterprise_team_managed?
    # TODO: filter out non-members?

    # TODO: handle IdP
    # if !team_destroyed && !force &&
    #   scim_managed_enterprise? &&
    #   externally_managed?
    #   # there is only one external identity linked to an EMU user
    #   identity = user.external_identities.first
    #   # Prevent removal of a user linked to an external group
    #   return if identity && external_group_team&.member?(identity.id)
    # end

    user_ids_to_remove_from_orgs = T.let([], T::Array[Integer])

    repo_ids = direct_or_inherited_repo_ids(affiliation: :all)
    memberships = Team::Membership.new(
      self,
      users.map(&:id),
      repo_ids,
      send_notification: send_notification,
      team_destroyed: team_destroyed,
    )

    memberships.bulk_remove(users: users, queue_delete_jobs: queue_delete_jobs, caller_type: caller_type)
    reload

    # Unsubscribe user from this and all parent teams they are not a member of anymore
    team_ids = ancestor_ids + [self.id]
    Team::Destruction::DestroySubscriptionsOperation.new(users.map(&:id), team_ids).execute

    # TODO: SCIM specific stuff out of scope until ESM users have GHES SCIM (see remove_member)
    users.each do |user|
      unless GitHub.esm_enabled? && caller_type == :enterprise_team
        instrument :remove_member, user: user
      end
      # TODO: can batch instrumentation later
      GlobalInstrumenter.instrument("team.remove_member", {
        user: user,
        team: self,
        action: :remove,
      })
      DenyForkCollabStateForUserPullRequestsJob.perform_later(
        user_id: user.id,
        resource_id: self.id,
        resource_class: self.class.name,
      )
    end

    Contribution.bulk_clear_caches_for_users(users, context: "bulk_remove_org_team_members")
  end

  # Public: remove a user from the team.
  #
  # user  - the User to be removed.
  # force - skip the expensive membership check and cache refresh, used in batch
  #         operations when removing many users at once.
  # send_notification - whether to notify the user they've been removed
  # team_destroyed - whether or not the user is being removed as part of the
  #                  team being destroyed.
  #
  # Returns nothing.
  def remove_member(user, force: false, send_notification: true, team_destroyed: false, queue_delete_jobs: true, caller_type: nil)
    return unless force || member?(user)

    return if !force && !team_destroyed && caller_type != :enterprise_team && self.enterprise_team_managed?

    if !team_destroyed && !force &&
      scim_managed_enterprise? &&
      externally_managed?
      # there is only one external identity linked to an EMU user
      identity = user.external_identities.first
      # Prevent removal of a user linked to an external group
      return if identity && external_group_team&.member?(identity.id)
    end

    repo_ids = direct_or_inherited_repo_ids(affiliation: :all)
    membership = Team::Membership.new(self, user.id, repo_ids, send_notification: send_notification, team_destroyed: team_destroyed)
    membership.remove(queue_delete_jobs: queue_delete_jobs, caller_type: caller_type) do
      reload
      user.reload

      # Unsubscribe user from this and all parent teams they are not a member of anymore
      team_ids = ancestor_ids + [self.id]
      Team::Destruction::DestroySubscriptionsOperation.new([user.id], team_ids).execute

      unless EnterpriseTeam.enabled_for_organizations?(business: self.organization&.business) &&
        caller_type == :enterprise_team
        instrument :remove_member, user: user
      end
      GlobalInstrumenter.instrument("team.remove_member", {
        user: user,
        team: self,
        action: :remove,
      })

      if scim_managed_enterprise?
        # remove organization membership entry if the user is an emu user or in GHES and the team is externally managed (checks in the org method)
        if EnterpriseTeam.enabled_for_organizations?(business: T.must(organization).business)
          organization&.remove_organization_membership_entry_with_adder_type(user: user, derived: true, adder_id: id, adder_type: :external_team)
        else
          organization&.remove_organization_membership_entry(user: user, derived: true, adder_id: id)
        end

        # EMUs + Enterprise Team synced members should not be removed if they have any org memberships
        unless organization&.prevent_removal_of_scim_managed_user?(user: user, reason: :any, db_connection: :writing)
          begin
            organization&.remove_member(user, send_notification: send_notification)
          rescue Organization::NoAdminsError, Organization::UnableToRemoveEmuError, Organization::UnableToRemoveEnterpriseTeamMemberError
          end
        end
      end
    end

    DenyForkCollabStateForUserPullRequestsJob.perform_later(user_id: user.id, resource_id: self.id, resource_class: self.class.name)

    Contribution.clear_caches_for_user(user, context: "remove_org_team_member")

    user
  end

  # Public: remove a repository from a team directly. This skips any
  # validations, instrumentation, or cleanup, and is used by the owners team
  # migration code.
  #
  # Returns nothing.
  def remove_repository_directly(repo)
    repo.remove_team self
    repo.reload # clear cached associations, e.g. list of teams
  end

  # Public: remove a repository from the team.
  #
  # repository - the Repository to be removed.
  #
  def remove_repository(repo, inline_fork_cleanup: false)
    return unless repository_ids.include?(repo.id)
    return if repo.access_group_setting&.includes_team?(self.id)

    repo.remove_team self

    instrument :remove_repository, repo: repo

    descendant_member_ids = Team.member_ids_of(self.id, immediate_only: false)
    if inline_fork_cleanup
      repo.remove_inaccessible_forks_for(descendant_member_ids)
    else
      if repo.private?
        Team.queue_fork_cleanup repo.id, descendant_member_ids
      end
    end

    Team.queue_clear_team_memberships(member_ids, organization_id, { repo: repo.id })

    repo.reload # clear cached associations, e.g. list of teams
  end

  # Public: enqueues a job to remove a repository from the team.
  #
  # repository - the Repository to be removed.
  #
  def enqueue_remove_repository(repo)
    return unless repository_ids.include?(repo.id)
    RemoveTeamFromRepoJob.perform_later(team: self, repo: repo)
  end

  # Public: Add a Project to this team.
  #
  # repo - the Project to add.
  # action - the permission this project should be added with.
  #          Valid values are :read, :write, or :admin
  #
  # Returns true if successful, false if not.
  def add_project(project, action)
    # Require a valid action.
    if Ability.valid_actions.exclude?(action)
      return ModifyProjectStatus::NO_PERMISSION
    end

    # Only permit organization-owned projects.
    if project.owner_type != "Organization"
      return ModifyProjectStatus::NON_ORGANIZATION_PROJECT
    end

    # Only permit projects owned by this team's organization.
    if project.owner_id != organization_id
      return ModifyProjectStatus::NOT_OWNED
    end

    # Don't add a project twice to the same team.
    if projects.exists?(project.id)
      return ModifyProjectStatus::DUPE
    end

    project.update_team_permission(self, action)

    ModifyProjectStatus::SUCCESS
  end

  # Public: Update project permission for this team.
  #
  # project - the Project to update.
  # action - the permission this project should be changed to.
  #          Valid values are :read, :write, or :admin
  #
  # Returns true if successful, false if not.
  def update_project_permission(project, action)
    ability = Authorization.service.direct_ability_between(actor: self, subject: project)

    return false if ability.nil?

    project.update_team_permission(self, action)

    true
  end

  # Public: remove a project from the team.
  #
  # project - the Project to be removed.
  #
  # Returns true if successful, false if not.
  def remove_project(project)
    return true if projects.exclude?(project)

    project.update_team_permission(self, nil)
    instrument :remove_project, project: project

    true
  end

  # Public: Request membership for a user
  #
  # user - The user requesting membership
  def request_membership(user)
    team_membership_requests.create(requester: user)
  end

  # Internal: subscribe a user to the team and every repository this team has
  # at least push on. Called when a user is added.
  def auto_subscribe_user(user)
    settings_response = GitHub.newsies.settings(user)

    # Only auto-subscribe the user to the team and its ancestors if they are auto-watching teams.
    if settings_response.success? && settings_response.auto_subscribe_teams?
      GitHub.newsies.subscribe_to_list(user, self)

      ancestors.each do |ancestor|
        GitHub.newsies.subscribe_to_list(user, ancestor)
      end
    end

    # Only auto-subscribe the user to the team's repositories if they are auto-watching repos.
    return if settings_response.success? && !settings_response.auto_subscribe_repositories?

    # We do this in batches as large orgs may have many repositories
    # https://github.com/github/github/issues/92298
    owned_repos = T.must(organization).repositories.owned_by(organization).pluck(:id)
    owned_repos.each_slice(AUTO_SUBSCRIBE_BATCH_SIZE) do |slice|
      repo_ids = Ability.where(
        actor_id: id_and_ancestor_ids,
        actor_type: "Team",
        subject_type: "Repository",
        subject_id: slice,
        action: [Ability.actions[:write], Ability.actions[:admin]],
        priority: Ability.priorities[:direct],
      ).pluck(:subject_id)

      unless repo_ids.empty?
        GitHub.newsies.async_auto_subscribe(user, repo_ids)
      end
    end
  end

  # Internal: queue up a job to add forks to team
  def add_forks_of(repo)
    TeamAddForksJob.perform_later(self, repo)
  end

  # Internal: add forks to team
  def add_forks_of!(repo)
    perm = permission_for(repo)
    if perm
      repo_ids = repository_ids
      repo.forks.each do |fork|
        # don't add repo to team twice
        if repo.fork_inherits_teams?(fork) && permission_for(fork).blank?
          throttle do
            add_repository(fork, perm, repo_ids: repo_ids)
          end
        end
      end
      update_repo_permissions_for_forks(repo) unless perm == permission_for(repo)
    end
  end

  # Public: queue a job to clear team membership info for an organization in
  # slices. Delegates to GitHub::Jobs::ClearTeamMembership.
  def self.queue_clear_team_memberships(access_list, org_id, options)
    return if access_list.blank?

    Array(access_list).each_slice(100_000) do |slice|
      ClearTeamMembershipsJob.perform_later(org_id, slice, options)
    end
  end

  # Public: queue a job to remove private forks of all repositories the
  # given user ids no longer have access to.
  def self.queue_fork_cleanup(repo_ids, user_ids)
    RemoveForksForInaccessibleRepositoriesJob.perform_later(Array(repo_ids), Array(user_ids))
  end

  # An "owners" team can never have its name changed.
  def restrict_changes_to_owners_team
  end

  # Internal: before_validation hook: set explicit permission if not set.
  def set_default_permission
    self.permission = DEFAULT_PERMISSION if self.permission.blank?
  end

  # Public: a list of members sorted by login
  def members_sorted_by_login
    members.sort_by { |u| u.login.downcase }
  end

  def async_ranked_members_for(user, scope:, direction: :desc)
    user.async_following.then do
      T.unsafe(User).ranked_for(user, scope: scope, direction: direction)
    end
  end

  # Public: Get team members that are ordered such that the users most relevant to the given
  # user are first.
  #
  # user - a User
  # scope - a User ActiveRecord relation to filter the members further, should be joined to
  #         abilities table as 'ab'
  # direction - Symbol for ordering, :desc or :asc for descending or ascending order.
  #
  # Returns a User scope.
  def ranked_members_for(user, scope:, direction: :desc)
    async_ranked_members_for(user, scope: scope, direction: direction).sync
  end

  # The user who performed the action as set in the GitHub request context. If the context doesn't
  # contain an actor, fallback to the ghost user.
  def actor
    @actor ||= (User.find_by(id: GitHub.context[:actor_id]) || User.ghost)
  end

  # Internal: event prefix for team instrumentation
  def event_prefix
    :team
  end

  # Internal: payload for team instrumentation
  def event_payload
    {
      event_prefix => self,
      :org         => organization,
      :ldap_mapped => ldap_mapped?,
      :note        => "Team #{self}",
    }
  end

  def event_context(prefix: event_prefix)
    {
      prefix => to_s,
      "#{prefix}_id".to_sym => id,
    }
  end

  # Internal: generates additional data to send for webhook payloads
  def webhook_payload(action)
    event_actor = (action == :created ? creator : actor)

    {
      spammy: event_actor.try(:spammy?),
      team_id: self.id,
    }.tap do |p|
      if event_actor
        if event_actor.class.to_s == "User"
          p[:actor] = event_actor
          p[:actor_id] = event_actor.id
        elsif actor
          p[:actor] = actor
          p[:actor_id] = actor.id
        end
        p[event_actor.event_prefix] = event_actor
      end
    end
  end

  # Internal: send email notifications when user added?
  def send_user_added_notifications?
    # Team membership doesn't get you a notification unless there's repos too.
    send_notifications? && repository_ids.any?
  end

  # Internal: Can we send notifications?
  #
  # Returns a boolean.
  def send_notifications?
    GitHub.send_notifications?
  end

  # Internal: Are team notifications disabled for the team?
  #
  # Returns a boolean.
  def notifications_disabled?
    notification_setting == NOTIFICATIONS_DISABLED
  end

  # Internal: after_update callback. Updates this team's permissions on each of
  # its repositories to match its "permission" attribute.
  #
  # On orgs with direct org membership enabled, this should never run, since
  # teams are no longer supposed to have a team-wide permission level.
  #
  # Returns nothing.
  def update_repository_grants
    true
  end

  def instrument_creation
    instrument :create, webhook_payload(:created)
  end

  def instrument_update
    return if previous_changes.empty?

    changes_payload = {}.tap do |hash|
      hash[:old_description] = previous_changes["description"].first if previous_changes["description"].present?
      hash[:old_name] = previous_changes["name"].first if previous_changes["name"].present?
      old_privacy = previous_changes["privacy"]
      if old_privacy.present?
        hash[:old_privacy] = old_privacy.first
      end
    end

    return if changes_payload.empty?

    GitHub.instrument "team.update", webhook_payload(:edited).merge(changes: changes_payload)
  end

  def instrument_rename
    instrument :rename,
      name: name,
      name_was: name_before_last_save
  end

  def instrument_change_privacy
    instrument :change_privacy,
      privacy: privacy,
      privacy_was: privacy_before_last_save
  end

  # Internal: an after_create hook. FIX: This should be done in Org#create_team
  # instead of a callback.
  def add_team_as_org_dependent
    T.must(organization).dependent_added(self)
  end

  def owning_organization_id
    organization_id
  end

  def owning_organization_type
    "Organization"
  end

  # Public: Get a recent pending invitation for the specified user that includes
  # this team.
  #
  # user - User to get the invitation for.
  #
  # Returns an OrganizationInvitation, or nil if there are no pending
  # invitations for the specified user.
  def pending_invitation_for(user)
    start = Time.now
    org_invitation = T.must(organization).pending_invitation_for(user)

    invitation = if org_invitation && org_invitation.includes_team?(self)
      org_invitation
    end
    ms = (Time.now - start) * 1000
    GitHub.dogstats.distribution("organization.invitations.dist.team_pending_invitation_for", ms)
    invitation
  end

  # Public: Get the membership state of the specified user for this team. This
  # is intended to be used by the API only.
  #
  # user - User to check the membership state for.
  #
  # Returns :pending, :active, or :inactive.
  def membership_state_of(user, immediate_only: true)
    if self.class.member_of?(id, user&.id, immediate_only: immediate_only)
      :active
    elsif pending_invitation_for(user).present?
      :pending
    else
      :inactive
    end
  end

  # Public: Determine what action the specified user can take to change their
  # membership on this team. This is intended to be used by the
  # membership_toggle view only.
  #
  # user - User to check the membership action for.
  #
  # Returns :leave, :leave_disabled, :join, :request_pending, :request_membership, or :ldap_mapped.
  def available_membership_action_for(user)
    if leavable_by?(user)
      :leave
    elsif member?(user)
      :leave_disabled
    elsif joinable_by?(user)
      :join
    elsif !T.must(organization).adminable_by?(user)
      # check for pending membership requests for viewer
      if pending_team_membership_requests.where(requester_id: user.id).any?
        :request_pending
      else
        :request_membership
      end
    elsif ldap_mapped?
      :ldap_mapped
    else
      Failbot.report!(Platform::Objects::Team::ViewerMembershipError.new("Unexpected viewer abilities"),
        app: "github-abilities",
        org_id: T.must(organization).id,
        team_id: id,
        user: user,
      )
      if pending_team_membership_requests.where(requester_id: user.id).any?
        :request_pending
      else
        :request_membership
      end
    end
  end

  # Public: Add or Update repository permission for this team.
  #
  # repo                  - the Repository
  # perm                  - the permission this team should have for this repo
  #
  # Returns an ModifyRepositoryStatus.
  def add_or_update_repository(repo, perm)
    return ModifyRepositoryStatus::REPOSITORY_LOCKED if repo.locked?

    if repository_ids.include?(repo.id)
      update_repository_permission(repo, perm)
    else
      add_repository(repo, perm)
    end
  end

  # Public: Update repository permission for this team.
  #
  # repo      - the Repository.
  # perm      - the String or Symbol name of the permission this team should have for this repo.
  #             It can be pull/push, read/triage/write/maintain/admin or a custom role name.
  # context   - Hash of Strings with the actor's previous Role {:old_permission, :old_base_role}
  #             A team might be given the same custom role permission, with a different base role.
  #             In these scenarios, the name is the same, but the Ability must be updated.
  #             For auditing purposes, we need the old Role and it's base role.
  #             A custom role is a user created role which inherits from any Role::VALID_REPO_BASE_ROLES
  #             with an additional set of fine grained permissions.
  #
  # Returns an ModifyRepositoryStatus.
  def update_repository_permission(repo, perm, context: {})
    # Only permit org-owned repos
    org_id = organization_id
    if repo.organization_id != org_id && repo.plan_owner.id != org_id
      return ModifyRepositoryStatus::NOT_OWNED
    end

    # Advisory temporary private fork access must be managed through its advisory
    return ModifyRepositoryStatus::ADVISORY_WORKSPACE if repo.advisory_workspace?

    # input action can be in permission or ability format
    repo_permission_role = RepositoryRole.by_name(perm: perm, org: repo.owner)

    new_base_role = !repo_permission_role.nil? && repo_permission_role.custom? ? repo_permission_role.base_role : nil

    if repo_permission_role.nil?
      return ModifyRepositoryStatus::NO_PERMISSION
    end

    return ModifyRepositoryStatus::GROUP_SETTINGS if repo&.access_group_setting&.deny_role_change?(self.id, perm)

    # if the custom role itself got updated, the old permission can't be obtained directly from Ability records
    # so we leverage the context
    old_role = RepositoryRole.by_name(perm: repo.direct_role_for(self), org: repo.owner)
    old_role_name = context.dig(:old_permission) || old_role&.name
    old_base_role_name = context.dig(:old_base_role) || old_role&.base_role&.name
    # for system roles we need to use the role name, in the case of a custom role, we need to use the base role
    old_permission = old_base_role_name.nil? ? old_role&.name : old_base_role_name

    if duplicate_permission?(new_permission: repo_permission_role.name, old_permission: old_role_name, old_base_role: old_base_role_name, repo: repo)
      return ModifyRepositoryStatus::DUPE
    end

    promises = []
    promises << repo.async_pullable_by?(self)
    promises << repo.async_pushable_by?(self)
    promises << repo.async_adminable_by?(self)
    promises << permission_greater_than_target?(old_permission, target: "triage")
    promises << permission_greater_than_target?(old_permission, target: "maintain")

    old_permissions = Promise.all(promises).then do |results|
      {
        pull: results[0],
        push: results[1],
        admin: results[2],
        triage: results[3],
        maintain: results[4]
      }
    end.sync

    # Do it.
    begin
      ActiveRecord::Base.connected_to(role: :writing) { repo.add_team self, action: repo_permission_role.name.to_sym }
    rescue ActiveRecord::RecordNotUnique
      return ModifyRepositoryStatus::DUPE
    rescue ActiveRecord::RecordInvalid => e
      # This can happen with overeager actors. We had a user that caused this error in multiple places of the api.
      # We can at least handle it here so we don't get paged.
      return ModifyRepositoryStatus::DUPE if e.message.include?("has already been taken")
      raise e
    end

    instrument :update_repository_permission, \
      { repo: repo,
        id: "#{event_prefix}.update_repository_permission.#{repo.id}",
        new_repo_permission: repo_permission_role.name,
        new_repo_base_role: new_base_role&.name,
        old_repo_permission: old_role_name,
        old_repo_base_role: old_base_role_name,
        old_permissions: old_permissions,
      }.merge(webhook_payload(:edited))

    GitHub.dogstats.increment("org.team.update_repository_permission")

    # apply to all forks of parent repos
    unless repo.fork?
      update_repo_permissions_for_forks(repo)
    end

    if old_permission == "read" && repo.pushable_by?(self)
      GitHub.newsies.async_subscribe_users_to_repository(repo.id, members.map(&:id))
    end

    ModifyRepositoryStatus::SUCCESS
  end

  # Public: Enqueue a jobs to update `batch_size` teams at a time.
  #
  # teams_repos   - The team and associated repos to be updated.
  # action        - The permission or role invitation is being updated to.
  # role          - the custom Role (default: nil)
  # context       - Hash of Strings with the teams' previous Role {:old_permission, :old_base_role}
  # actor_id      - The actor updating the permissions
  # batch_size    - Batch size to be passed processed.
  #
  def self.batch_enqueue_update_repo_permissions(teams_repos:, action:, role: nil, context: {}, actor_id: T.unsafe(self).organization.id, batch_size: TEAM_UPDATE_BATCH_SIZE)
    teams_repos.each_slice(batch_size) do |teams_repos_slice|
      BatchUpdateTeamRepoPermissionsJob.perform_later(teams_repos_slice, actor_id, action: action, role: role, context: context)
    end
  end

  def enqueue_update_repo_permissions(repo:, action:)
    check_valid_action(action, repo)
    UpdateTeamRepoPermissionsJob.perform_later(self, action: action, repo: repo)
  end

  def check_valid_action(action, repo)
    valid_action = PERMISSIONS.include?(action.to_s) || ABILITIES.include?(action.to_s) || Role.valid_custom_role?(action, owner: repo.owner)
    raise ArgumentError, "Invalid permission #{action}" unless valid_action
  end

  # Internal: apply permission to all forks of a repo in a background job
  def update_repo_permissions_for_forks(repo)
    TeamUpdateForkedRepositoryPermissionsJob.perform_later(id, repo.id, actor.id)
  end

  # Internal: Validates that a team's name and slug are unique by the team's
  # organization. Why not just use `validates_uniqueness_of`? We have added a
  # boolean attribute to the teams table called `deleted`. It exists so that
  # users do not see teams they have just deleted but are still queued to be
  # deleted by us.
  #
  # So this check, essentially does what `validate_uniqueness_of` does but
  # ensures we are only checking against teams that have not been marked as
  # deleted.
  def name_and_slug_uniqueness_by_org
    Team
      .owned_by(organization)
      .where(deleted: false)
      .where.not(id: id)
      .pluck(:name, :slug).each do |(existing_name, existing_slug)|
      errors.add :name, "must be unique for this org" if existing_name.casecmp?(self.name) # case_insensitve
      errors.add :slug, "must be unique for this org" if existing_slug == self.slug # case_sensitive
    end
  end

  # Internal: Validates that a team's parent is a member of the same org
  def validate_parent_team_is_in_org
    if (team = parent_team) && team.organization_id != organization_id
      errors.add :parent_team_id, "must be a member of the same org"
    end
  end

  # Internal: Validates that a cycle is not created
  def validate_parent_team_does_not_cause_cycle
    return unless parent_team

    path = Arvore::PathString.new(parent_team.tree_path)
    if path.include?(id)
      errors.add :parent_team_id,  "can't be a child of the current team"
      nil
    end
  end

  # Internal: Validate that a parent is not secret
  def validate_parent_not_secret
    if (team = parent_team) && team.secret?
      errors.add :parent_team_id, "can't be a secret team"
    end
  end

  def validate_parent_has_no_group_mappings
    if parent_team&.externally_managed?
      errors.add :parent_team_id, "can't have team sync enabled"
    end
  end

  def validate_parent_is_not_enterprise_team_managed
    if parent_team&.enterprise_team_managed?
      errors.add :parent_team_id, "can't be enterprise team managed"
    end
  end

  # Internal: Validate that the team is not secret and a parent or child at the same time.
  def validate_secret_or_nested
    if secret?
      errors.add :visibility, "can't be secret for a child team" if parent_team
      errors.add :visibility, "can't be secret for a parent team" if tree_path && child_teams.any?
    end
  end

  # Internal: Validate that requesting team is allowed to create parent requests for this team
  def allows_change_parent_requests_from?(requesting_team)
    requesting_team.organization_id == self.organization_id
  end

  # Public: Returns a scope for any pending change parent requests from a given direction
  def pending_change_parent_requests(direction: nil)
    allowed_request_directions = %w(inbound_parent_initiated inbound_child_initiated
      outbound_parent_initiated outbound_child_initiated)

    field = direction&.include?("parent") ? :parent_team : :child_team

    scope = if allowed_request_directions.include?(direction)
      ::TeamChangeParentRequest.public_send(direction, self).order_by_team_name(field)
    else
      ::TeamChangeParentRequest.involving(self)
    end.pending
  end

  # Public: Attempts a team update on behalf of a user, including changes to this team's
  #         parent team. In order to be reused by mutations/update_team, it returns a success bool
  #         and a hash of errors
  def request_update_on_behalf_of(actor, attributes, inputs, privacy: nil, group_mappings: nil)
    requests_to_cancel = []
    attributes[:updater] ||= actor

    # Includes some update to the parent team
    if inputs.key?(:parent_team)
      new_parent_team = inputs[:parent_team]
      if new_parent_team
        pending_requests = TeamChangeParentRequest.identical_to(
          new_parent_team.id,
          self.id,
        ).pending

        new_parent_team_owns_existing_parent_team = self.parent_team.present? && new_parent_team.ancestor_of?(self.parent_team)

        if new_parent_team.id == self.parent_team_id || new_parent_team_owns_existing_parent_team || new_parent_team.updatable_by?(actor)
          attributes[:parent_team_id] = new_parent_team.id
          requests_to_cancel = pending_requests
        elsif pending_requests.empty?
          # It's okay to create a duplicate request, as long as there are no
          # pending requests and the parent team isn't already the team's parent.
          GitHub.logger.info("TeamChangeParentRequest required",
            "gh.team.id": self.id,
            "gh.parent_team.id": new_parent_team.id,
            "enduser.id": actor.id,
          )

          begin
            request = ::TeamChangeParentRequest.create_initiated_by_child!(
              parent_team: new_parent_team,
              child_team: self,
              requester: actor,
            )
          rescue ActiveRecord::RecordInvalid => e
            self.errors.add(:base, "There was an issue with your request")
            return [false, { type: :unprocessable, message: "There was an issue with your request" }]
          end
        end
      else
        GitHub.logger.info("setting parent_team_id to nil",
          "gh.team.id": self.id,
          "enduser.id": actor.id,
        )
        attributes[:parent_team_id] = nil
      end
    end

    # Includes some update to the privacy
    if attributes[:privacy] == "secret"
      requests_to_cancel += TeamChangeParentRequest.involving(self).pending
    end

    transformed_group_mappings = Array(group_mappings.map(&:to_h)) if group_mappings
    Team::Editor.update_team(self, group_mappings: transformed_group_mappings, **attributes)

    if self.errors.empty?
      Array(requests_to_cancel).uniq.each do |request|
        request.cancel(actor: actor)
      end
      [true, nil]
    else
      [false, { type: :invalid, message: self.errors.full_messages.join(", ") }]
    end
  end

  def reload(*)
    super.tap do
      reset_parent_team
    end
  end

  # Public: Do any members have higher access to the specified repo than this
  # team provides?
  #
  # repo - Repo to check access level of.
  #
  # Returns a boolean.
  def members_with_higher_access_to?(repo)
    case Authorization.service.most_capable_action_between(actor: self, subject: repo)
    when "read"
      members.any? { |member| repo.pushable_by?(member) }
    when "write"
      members.any? { |member| repo.adminable_by?(member) }
    else
      false
    end
  end

  def primary_avatar_path
    "/t/#{id}"
  end

  def tenant_slug_for_avatar
    return "" unless GitHub.multi_tenant_enterprise?

    # System accounts are belong to entities whose business_id is equal to zero
    return GitHub.company_specific_entity_acronym if T.must(organization).business_id.zero?

    # Teams will always attached to an Organization. On line 166, we validate the presence of `organization_id`
    T.must(organization).business&.slug
  end

  def keep_old_avatar?
    false
  end

  def avatar_editable_by?(actor)
    adminable_by?(actor)
  end

  def cant_change_visibility?
    parent_team.present? || has_child_teams? || enterprise_team_managed?
  end

  def strip_name
    self.name = self.name&.strip
  end

  # Public: Check if the team has explicit memberships
  #
  # Teams with explicit members are prevented to be linked to IdP provided groups.
  #
  # Returns Boolean
  def explicit_members?
    return false if external_group_team.present?
    members.any?
  end

  # Public: Is this team externally managed via Team Sync or externally managed by an external group SCIM?
  #
  # Returns a boolean
  def externally_managed?
    return true if external_group_team.present?
    organization&.team_sync_enabled? && group_mappings.any?
  end

  # Public: Is this team externally managed via Team Sync or externally managed by an external group SCIM?
  #
  # Returns a Promise that resolves to a Boolean.
  def async_externally_managed?
    Promise.all([async_external_group_team, async_organization]).then do |external_group_team, organization|
      next true if external_group_team.present?
      organization.async_team_sync_enabled?.then do |enabled|
        next false unless enabled
        async_group_mappings.then do |mappings|
          mappings&.any?
        end
      end
    end
  end

  # Public: Is this team managed locally (not via Team Sync, externally managed by an external group SCIM, or managed by an Enterprise Team)?
  #
  # Returns a boolean
  def locally_managed?
    !externally_managed? && !enterprise_team_managed?
  end

  # Public: Is this team locally managed and not via Team Sync, not externally managed by an external group SCIM, and not managed by an enterprise team?
  #
  # Returns a Promise that resolves to a Boolean.
  def async_locally_managed?
    Promise.all([async_external_group_team, async_organization, self.async_enterprise_team_managed?]).then do |external_group_team, organization, enterprise_team_managed|
      next false if external_group_team.present?
      next false if enterprise_team_managed
      organization.async_team_sync_enabled?.then do |enabled|
        next true unless enabled
        async_group_mappings.then do |mappings|
          !mappings&.any?
        end
      end
    end
  end

  # Public: Is this team managed by an enterprise team?
  #
  # Returns a boolean
  sig { returns T::Boolean }
  def enterprise_team_managed?
    async_enterprise_team_managed?.sync
  end

  # Public: Is this team managed by an enterprise team?
  #
  # Returns a boolean
  sig { returns Promise[T::Boolean] }
  def async_enterprise_team_managed?
    # Introduced the async version to solve the association loading error from graphql queries hitting admin permission checks.
    async_organization.then do |organization|
      Promise.all([async_enterprise_team_organization_mapping, organization&.async_business]).then do |enterprise_team_organization_mapping, business|
        EnterpriseTeam.enabled_for_organizations?(business: business) && enterprise_team_organization_mapping.present?
      end
    end
  end

  # Public: Can this team be externally managed via Team Sync?
  #
  # Returns a boolean
  def can_be_externally_managed?
    async_can_be_externally_managed?.sync
  end

  # Public: Can this team be externally managed via Team Sync?
  #
  # Returns a Promise that resolves to a boolean
  def async_can_be_externally_managed?
    organization&.async_team_sync_enabled?.then do |enabled|
      enabled && !has_child_teams?
    end
  end

  # Public: Given a user and a query, search for teams that could potentially be
  # child teams. Filter by authorization and possibly by the query. Then
  # decorate the resulting teams with eligibility_status values as a form of
  # validation.
  #
  # Returns: Promise of Array of Teams
  def async_potential_child_teams(viewer:, query:)
    async_organization.then do |org|
      scope = org.visible_teams_for(viewer)
        .where.not(id: id)

      if scim_managed_enterprise?
        scope = scope.not_externally_managed
      end

      scope.then { |teams| Team.search_name_and_slug(query: query, scope: teams) }
        .map { |team| team.determine_child_team_eligibility(viewer, self) }
    end
  end

  # Internal: Determine if a team is eligibly to be a child of the current team.
  # We use various criteria to decorate the team object with information about
  # whether a team is eligible to be a child team and why it is not eligible if
  # it is not.
  #
  # Returns: a team.
  protected def determine_child_team_eligibility(viewer, parent_team)
    tap do |team|
      team.eligibility_status =
        case
        when secret? then ELIGIBLITY_STATUSES[:secret]
        when ancestor_of?(parent_team) then ELIGIBLITY_STATUSES[:ancestor]
        when parent_team_id == parent_team.id then ELIGIBLITY_STATUSES[:child]
        when adminable_by?(viewer) then ELIGIBLITY_STATUSES[:eligible]
        else ELIGIBLITY_STATUSES[:permission]
        end
    end
  end

  # Public: Does the given team's ancestors include the team in question?
  #
  # Returns: Boolean.
  def ancestor_of?(possible_child)
    possible_child.ancestor_ids.include?(id)
  end

  # The class name persisted as `target_type` when a UserRole is created
  # with this object as target.
  #
  # Returns: String
  def user_role_target_type
    self.class.user_role_target_type
  end

  def target_for_conditional_access
    # In the CAP framework, TFCA refers to the entity governing
    # the conditional access rules that grant access to resources they own.
    # If any changes are done to this method, please loop in @github/authorization.
    # https://thehub.github.com/engineering/development-and-ops/dotcom/cap/how-does-cap-evaluation-work/#target-for-conditional-access-tfca
    organization
  end

  def async_target_for_conditional_access
    async_organization
  end

  # Determines the target for for conditional access for multiple teams instances
  #
  # business - an enumerable of Teams
  #
  # returns Hash[Teams] => target for conditional access
  def self.multiple_target_for_conditional_access(teams)
    ConditionalAccess::Filter.ensure_with_class(teams, Team)
    orgs = Organization.where(id: teams.pluck(:organization_id))
    id_to_owner = orgs.each_with_object({}) { |v, h| h[v.id] = v }
    result = {}
    teams.each do |team|
      result[team] = id_to_owner[team.organization_id]
    end

    result
  end

  # Public: retrieve the child teams for the user based on the provided query
  #
  # query - a TeamSearchQuery
  # user  - the User in question
  # immediate_only  - return only immediate child teams
  # order_by_name_asc  - return results ordered by team name
  #
  # Returns a Team scope
  def team_search_for_user(query, user, immediate_only: false, order_by_name_asc: false)
    scope = if query.members_filter.present?
      if query.members_filter == "me"
        descendants_where_user_is_a_member(user, immediate_only: immediate_only)
      elsif query.members_filter == "empty"
        descendants_without_members(immediate_only: immediate_only)
      end
    else
      descendants(immediate_only: immediate_only)
    end

    if query.users_filter.present?
      query.users_filter.each_with_index do |name, i|
        break if i > TeamSearchQuery::USER_FILTER_MAX
        if searched_user = User.find_by_login(name)
          searched_user_teams = descendants_where_user_is_a_member(searched_user)
          teams_scoped_to_searched_user = scope & searched_user_teams
          scope = Team.where(id: teams_scoped_to_searched_user.map(&:id))
        end
      end
      scope
    end

    if query.cleaned_query.present?
      scope = scope.where(["name LIKE ? OR slug LIKE ?", "%#{query.cleaned_query.strip}%", "%#{query.cleaned_query.strip}%"])
    end

    if order_by_name_asc
      scope = scope.order("name ASC")
    end

    scope
  end

  # Public: Determine if this team could become the child of another team.
  #
  # parent_team     - The candidate parent Team object
  #
  # Returns [boolean,string|nil], where the string is an error message if this
  # team could not be a valid child.
  def can_be_child_of?(parent_team)
    unless self.organization_id == parent_team.organization_id
      # Deliberately don't disclose the team name
      return [false, "Team is in a different organization"]
    end

    if parent_team.enterprise_team_managed?
      return [false, "Team is enterprise team managed and cannot become a child team."]
    end

    if self.ancestor_ids.include?(parent_team.id) || parent_team.parent_team_id == self.id
      return [false, "#{parent_team.name} is already related to #{self.name} and cannot become a child team."]
    end

    [true, nil]
  end

  def post_archive_readable_by?(viewer)
    # non members of a secret team should not be able to view archive link
    if self.secret? && !self.member?(viewer)
      return false
    end

    # only members with read access to the team can view the archive link
    T.must(self.organization).member?(viewer)
  end

  def get_team_posts_scope(current_user)
    user_is_member = self.member?(current_user)
    if user_is_member
      return DiscussionPost.where(team_id: self.id, transferred_discussion_id: nil).preload(:user)
    end

    DiscussionPost.where(team_id: self.id, transferred_discussion_id: nil, private: false).preload(:user)
  end

  # Public: If the team has a migration in progress for moving team discussions to repository-level discussions
  def team_discussion_migration_in_progress?
    !repository_id.nil? && !migration_complete
  end

  # Public: If the team has a migration that is resumable by stafftools
  def team_discussion_migration_can_be_resumed?
    !repository_id.nil?
  end

  def pending_invitations
    team_pending_invitations.where(organization_id: organization_id)
  end

  sig { returns(T::Boolean) }
  def business_team?
    false
  end

  sig { returns(T::Array[T.nilable(Integer)]) }
  def organization_ids
    [organization_id]
  end

  sig { returns(T.any(ActiveRecord::Relation, T::Array[Organization])) }
  def organizations
    Organization.where(id: organization_ids)
  end

  private

  def instrument_add_members(users, adder, caller_type = nil)
    users.map { |user| instrument_add_member(user, adder, caller_type) }
  end

  def instrument_add_member(user, adder, caller_type = nil)
    instrument_options = { user: user }
    instrument_options[:actor] = adder if adder.present?

    unless EnterpriseTeam.enabled_for_organizations?(business: self.organization&.business) &&
      caller_type == :enterprise_team
      instrument :add_member, instrument_options
    end
    GlobalInstrumenter.instrument("team.add_member", instrument_options.merge(
      team: self,
      action: :add,
    ))
  end

  # Private: Validates the users can be added to the team in bulk.
  # This method is used by the add_member_users_bulk method.
  #
  # Returns an AddMemberStatus array
  def bulk_validate_add_member_users(users, new_member_ids, options)
    adder = options[:adder]
    skip_organization_seat_checks = !!options[:skip_organization_seat_checks]

    # Only traditional users can belong to teams.  Also takes care of a nil user.
    return AddMemberStatus::NOT_USER if users.reject { |user| user.user? }.any?

    # get an array of user ids
    user_ids = users.map(&:id).sort

    # Check if the user is an an EMU that is externally managed
    if !options[:force_emu] &&
      scim_managed_enterprise? &&
      externally_managed?
      # there is only one external identity linked to an EMU user
      identity_ids = ActiveRecord::Base.connected_to(role: :reading) { ExternalIdentity.by_provider(T.must(organization).business&.external_provider).where(user_id: users.map(&:id)).pluck(:id) }
      external_group = external_group_team&.external_group
      external_group_membership_count = ActiveRecord::Base.connected_to(role: :reading) { ExternalIdentityGroupMembership.where(external_group_id: T.must(external_group).id, external_identity_id: identity_ids).count }
      return AddMemberStatus::BLOCKED if identity_ids.any? && external_group && external_group_membership_count != identity_ids.size
    end

    # Don't add a user to an org they have blocked.
    return AddMemberStatus::BLOCKED if T.must(organization).ignored_by_users.where(user_id: user_ids).exists?

    # Don't add a user to a team if the actor is blocked by the user
    return AddMemberStatus::BLOCKED if adder&.blocked_by?(users)

    # Don't add a user twice
    return AddMemberStatus::DUPE if (member_ids.sort & user_ids).any?

    unless skip_organization_seat_checks
      # Don't add if per seat organization has no seat for the user.
      return AddMemberStatus::NO_SEAT unless ActiveRecord::Base.connected_to(role: :reading) { T.must(organization).has_seats_for?(new_member_ids) } if new_member_ids.any?

      # Don't add if per seat organization has no seat for the user on pending
      # cycle.
      return AddMemberStatus::PENDING_CYCLE_NO_SEAT unless ActiveRecord::Base.connected_to(role: :reading) { T.must(organization).has_seats_for?(new_member_ids, pending_cycle: true) } if new_member_ids.any?
    end

    # 2FA is not required for EMU users
    unless scim_managed_enterprise?
      # Don't add if user doesn't satisfy the 2FA requirements of the Organization
      return AddMemberStatus::NO_2FA if users.reject { |user| T.must(organization).two_factor_requirement_met_by?(user) }.any?
    end

    # Don't add if user doesn't satisfy the github/Employees no-SMS 2FA requirement
    if github_employees_team? && users.flat_map { |user| user.sms_registrations }.any? && GitHub.flipper[:github_employees_no_sms_2fa].enabled?
      return AddMemberStatus::GITHUB_EMPLOYEE_NO_SMS_2FA
    end

    # Don't add if user doesn't satisfy the SAML SSO requirement of the Organization
    return AddMemberStatus::NO_SAML_SSO unless T.must(organization).meets_sso_requirements_for_users?(user_ids: user_ids)

    if GitHub.bypass_org_invites_enabled? && adder.present?
      AddMemberStatus::NO_PERMISSION unless actor_can_add_members?(new_member_ids, actor: adder)
    end
  end

  # Internal: when trying to update the permission on a repository, we must account for
  #           custom roles, which can have the same name, but different base roles.
  #           See #update_repository_permission
  def duplicate_permission?(new_permission:, old_permission:, old_base_role:, repo:)
    custom_role = RepositoryRole.custom_role_by_name(new_permission, owner: repo.owner)

    return new_permission == old_permission unless custom_role

    custom_role.name == old_permission && custom_role.base_role.name == old_base_role
  end

  # Internal: Is the permission greater or equal in rank than the target permission.
  # Both inputs can be an Ability (e.g. read), a Role (e.g. triage) or a custom role.
  #
  # - permission: a String or Symbol.
  # - target: a String or Symbol.
  #
  # Returns a Boolean.
  def permission_greater_than_target?(permission, target:)
    return false if permission.nil?

    perm = permission.to_sym
    target = target.to_sym
    return true if perm == target

    permission =
      if Role.valid_system_role?(perm)
        Role.preset_by_name(perm)
      else
        RepositoryRole.custom_role_by_name(perm, owner: organization)
      end

    permission.target_greater_than_or_equal_to_other_role?(other_role: target)
  end

  private def enqueue_handle_team_parent_changes
    HandleTeamParentChangesJob.perform_later(organization_id)
  end
end
