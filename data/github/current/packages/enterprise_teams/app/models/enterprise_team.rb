# typed: strict
# frozen_string_literal: true

class EnterpriseTeam < ApplicationRecord::Domain::Users
  include Instrumentation::Model

  COPILOT_TEAM_SUFFIX = "copilot-licensees"
  VALID_ORGANIZATION_SYNC_OPTIONS = %(disabled all)
  MAX_SYNC_MEMBERS = 5000
  DEFAULT_MAX_SYNC_ORGANIZATIONS = 5000
  BATCH_SIZE = 200

  belongs_to :business
  has_many :enterprise_team_assignments
  has_many :enterprise_team_group_mappings, -> { where(deleted_at: nil) }
  has_many :active_and_deleted_enterprise_team_group_mappings, class_name: "EnterpriseTeamGroupMapping"
  has_many :enterprise_team_memberships
  has_many :enterprise_team_organization_mappings

  destroy_dependents_in_background :enterprise_team_assignments
  destroy_dependents_in_background :active_and_deleted_enterprise_team_group_mappings
  destroy_dependents_in_background :enterprise_team_memberships
  destroy_dependents_in_background :enterprise_team_organization_mappings

  validates_presence_of   :name, :business_id, :slug
  validates :name, length: { maximum: 255 }
  validates :slug, uniqueness: { scope: :business_id }
  validate :name_and_slug_uniqueness_by_business
  validates_presence_of :sync_to_organizations, message: "Sync to organizations is required"
  validates_inclusion_of :sync_to_organizations, in: VALID_ORGANIZATION_SYNC_OPTIONS, message: "Invalid sync_to_organizations setting"
  validate :check_sync_to_organizations

  before_validation :set_slug
  before_validation :strip_name

  scope :owned_by, -> (business) { where(business_id: Array(business).map(&:id)) }
  scope :active, -> { where(deleted_at: nil) }
  scope :deleted, -> do
    unscope(where: :deleted_at).where.not(deleted_at: nil)
  end
  scope :filter_by_assignment_type, -> (assignment_type) { joins(:enterprise_team_assignments).where(enterprise_team_assignments: { assignment_type: assignment_type }) }
  scope :exclude_having_assignment, -> (assignment_type) { left_joins(:enterprise_team_assignments).group("enterprise_teams.id").having("SUM(CASE WHEN enterprise_team_assignments.assignment_type = ? THEN 1 ELSE 0 END) = 0", assignment_type) }

  default_scope { active }

  before_destroy :emit_unassignment_events

  after_commit :instrument_create, on: [:create]
  after_commit :instrument_destroy, on: [:destroy]
  after_update_commit :instrument_rename, if: :saved_change_to_name?

  NAME_SLUG_UNIQUE_BY_BUSINESS_ERROR = "must be unique for this business"

  sig { returns(Integer) }
  def self.max_sync_members
    MAX_SYNC_MEMBERS
  end

  sig { returns(Integer) }
  def self.max_sync_organizations
    GitHub.esm_max_sync_organizations_override || DEFAULT_MAX_SYNC_ORGANIZATIONS
  end

  sig { returns(T::Boolean) }
  def active?
    deleted_at.nil?
  end

  sig { returns(T::Boolean) }
  def soft_deleted?
    !active?
  end

  sig { returns(T::Boolean) }
  def copilot_enterprise_team?
    self.enterprise_team_assignments.exists? && self.enterprise_team_assignments.first&.assignment_type == "copilot"
  end

  sig { params(business: Business).returns(T.nilable(EnterpriseTeam)) }
  def self.get_copilot_team(business)
    business.enterprise_teams.active.filter_by_assignment_type(:copilot).first
  end

  sig { returns(T::Boolean) }
  def direct_memberships_enabled?
    !self.enterprise_team_group_mappings.exists?
  end

  sig { params(user: User).returns(T::Boolean) }
  def member?(user)
    if direct_memberships_enabled?
      self.enterprise_team_memberships.exists?(user_id: user.id)
    else
      self.enterprise_team_group_mappings.any? do |group|
        group.external_group&.active_user_ids&.include?(user.id)
      end
    end
  end

  sig { returns(T::Array[Integer]) }
  def member_user_ids
    if direct_memberships_enabled?
      self.enterprise_team_memberships.pluck(:user_id)
    else
      self.enterprise_team_group_mappings.flat_map do |group|
        group.external_group&.active_user_ids
      end.compact.uniq
    end
  end

  sig { params(user: User, business_ids: T.nilable(T::Array[Integer])).returns(T::Array[Integer]) }
  def self.all_visible_team_ids_for(user, business_ids: nil)
    all_visible_teams_for(user, business_ids: business_ids).pluck(:id)
  end

  sig { params(user: User, business_ids: T.nilable(T::Array[Integer])).returns(ActiveRecord::Relation) }
  def self.all_visible_teams_for(user, business_ids: nil)
    ids = if business_ids.nil? || business_ids.empty?
      GitHub.single_tenant_enterprise? ? [GitHub.global_business.id] : user.business_ids(include_unaffiliated: true)
    else
      business_ids
    end

    base_scope = EnterpriseTeam.where(business_id: ids)

    direct_teams = base_scope
      .left_joins(:enterprise_team_memberships)
      .where(enterprise_team_memberships: { user_id: user.id })

    idp_teams = base_scope
      .left_joins(enterprise_team_group_mappings: { external_group: { external_identity_group_memberships: :external_identity } })
      .where(external_identities: { user_id: user.id })
      .merge(ExternalIdentity.not_disabled_and_deleted)

    EnterpriseTeam.from(Arel::Nodes::TableAlias.new(direct_teams.arel.union(idp_teams.arel), :enterprise_teams))
  end

  sig { params(users: T::Array[User]).void }
  def bulk_add_members(users:)
    # TODO: Need assess if we should do checks against the actor's permissions, also additionally filter out users not
    # a part of the enterprise
    # https://github.com/github/Identity-Teams/issues/936
    return unless direct_memberships_enabled?

    # Remove nils from the array and continue with the batch
    users.compact!
    users.reject!(&:suspended?)
    return if users.empty?

    transaction do
      # Don't make unneeded inserts for members that already exist on the ET
      existing_member_ids = self.enterprise_team_memberships.pluck(:user_id)
      new_member_ids = (users.map(&:id) - existing_member_ids).uniq

      # The actual batch insert
      batch = new_member_ids.map do |member_id|
        {
          enterprise_team_id: self.id,
          user_id: member_id,
        }
      end
      with_write { EnterpriseTeamMembership.insert_all(batch) }
    end

    self.instrument_update
  end

  sig { params(user_ids: T::Array[Integer]).void }
  def bulk_add_member_ids(user_ids:)
    # TODO: Need assess if we should do checks against the actor's permissions, also additionally filter out users not
    # a part of the enterprise
    # https://github.com/github/Identity-Teams/issues/936
    return unless direct_memberships_enabled?

    # Remove nils from the array and continue with the batch
    user_ids.compact!
    return if user_ids.empty?

    # Don't make unneeded inserts for members that already exist on the ET
    existing_member_ids = self.enterprise_team_memberships.pluck(:user_id)
    new_member_ids = (user_ids - existing_member_ids).uniq

    transaction do
      new_member_ids.each_slice(BATCH_SIZE) do |member_ids|
        # The actual batch insert
        batch = member_ids.map do |member_id|
          {
            enterprise_team_id: self.id,
            user_id: member_id,
          }
        end
        with_write { EnterpriseTeamMembership.insert_all(batch) }
      end
    end

    self.instrument_update
  end

  sig { returns(Integer) }
  def member_count
    member_user_ids.count
  end

  sig { params(user_ids: T::Array[Integer], business_id: Integer).void }
  def self.destroy_memberships_for(user_ids:, business_id:)
    business = Business.find_by(id: business_id)
    return unless business&.enterprise_teams_enabled?

    EnterpriseTeamMembership.joins(:enterprise_team).where(
      enterprise_teams: { business_id: business_id },
      enterprise_team_memberships: { user_id: user_ids }
    ).in_batches(of: BATCH_SIZE) do |batch|
      with_write { batch.destroy_all }
    end
  end

  # Class method to determine if a given Business qualifies for Enterprise Team Managed Organization Teams.
  # This is based on the following:
  # 1. The enterprise_teams_enabled_for_organizations feature flag (GHEC) is enabled for the Business
  # 2. There is not a single global business for this environment
  # 3. The Business is on a non-basic plan
  # 4. A GHES environment has enterprise security manager enabled
  sig { params(business: T.nilable(Business)).returns(T::Boolean) }
  def self.enabled_for_organizations?(business:)
    return false if business.nil?

    return GitHub.esm_enabled? if GitHub.enterprise?

    return false if business.seats_plan_basic?

    return false unless GitHub.multi_tenant_enterprise? || Rails.env.development?

    ::SecurityCenter::FeatureFlagHelper.feature_flag :enterprise_teams_enabled_for_organizations, actors: [business]
  end

  sig { params(business: T.nilable(Business)).returns(T::Boolean) }
  def self.can_sync_all_orgs?(business:)
    return false if business.nil?
    return false if GitHub.esm_enabled?
    business.organizations.count <= max_sync_organizations && GitHub.multi_tenant_enterprise?
  end

  # Enterprise Team -> Org Team sync runs afoul of GitHub entitlement management in some orgs.
  # This lets the organizations the feature flag is enabled for opt out of the sync.
  sig { params(organization: T.nilable(Organization)).returns(T::Boolean) }
  def self.disabled_for_organization?(organization:)
    return false if organization.nil?

    GitHub.flipper[:enterprise_teams_disabled_for_organizations].enabled?(organization)
  end

  sig { params(business: T.nilable(Business)).returns(T::Boolean) }
  def self.enabled_for_organization_security_manager?(business)
    return false if business.nil?
    return false unless enabled_for_organizations?(business: business)
    return GitHub.esm_enabled? if GitHub.enterprise?
    ::SecurityCenter::FeatureFlagHelper.feature_flag :enterprise_teams_security_manager_sync, actors: [business]
  end

  sig { returns(T::Boolean) }
  def can_sync_to_organizations?
    can_sync_to_organizations_member_check? && EnterpriseTeam.can_sync_to_current_organization_count?(T.must(business))
  end

  sig { returns(T::Boolean) }
  def can_sync_to_organizations_member_check?
    member_user_ids.count <= EnterpriseTeam.max_sync_members
  end

  sig { params(business: Business).returns(T::Boolean) }
  def self.can_sync_to_current_organization_count?(business)
    business.feature_enabled?(:enterprise_team_org_sync_bypass_limit) ||
    (RepositorySecurityCenterConfig.where(ghas_enabled: true, owner_type: "ORGANIZATION", business_id: business.id).distinct.count(:owner_id) <= EnterpriseTeam.max_sync_organizations)
  end

  # currently, there are no constraints to grant a permission over a team over any target
  sig { params(subject: T.untyped, action: T.untyped).void }
  def can_be_granted_permission_over!(subject, action); end

  sig { returns(T::Boolean) }
  def sync_to_organizations?
    active? && sync_to_organizations == :all.to_s
  end

  sig { void }
  def instrument_create
    instrument_options = {
      business_id: business_id,
      business: business,
      enterprise_team_id: id,
      enterprise_team: self.slug,
    }
    instrument :create, instrument_options
  end

  sig { void }
  def instrument_update
    if EnterpriseTeam.enabled_for_organizations?(business: business)
      instrument :update,
        id: id
    end

    # also emit an update event on all ET assignments
    enterprise_team_assignments.each do |assignment|
      instrument :update,
        id: id,
        prefix: EnterpriseTeam.assignment_event_prefix(assignment.assignment_type)
    end
  end

  sig { params(operation: Symbol).void }
  def instrument_idp_group_mapping(operation)
    self.member_user_ids.each do |member|
      if operation == :provision
        instrument_add_member(User.find(member))
      elsif operation == :deprovision
        instrument_remove_member(User.find(member))
      end
    end
  end

  sig { void }
  def instrument_destroy
    instrument_options = {
      business_id: business_id,
      business: business,
      enterprise_team_id: id,
      enterprise_team: self.slug,
    }
    instrument :destroy, instrument_options
  end

  sig { void }
  def instrument_rename
    instrument_options = {
      name: name,
      name_was: name_before_last_save,
      business_id: business_id,
      business: business,
      enterprise_team_id: id,
      enterprise_team: self.slug,
    }
    instrument :rename, instrument_options
  end

  sig { params(user: User).void }
  def instrument_add_member(user)
    instrument_options = {
      user_id: user.id,
      user: user,
      business_id: business_id,
      business: business,
      enterprise_team_id: self.id,
      enterprise_team: self.slug,
    }
    instrument :add_member, instrument_options
  end

  sig { params(user: User).void }
  def instrument_remove_member(user)
    instrument_options = {
      user_id: user.id,
      user: user,
      business_id: business_id,
      business: business,
      enterprise_team_id: self.id,
      enterprise_team: self.slug,
    }
    instrument :remove_member, instrument_options
  end

  sig { params(assignment_type: String).returns(String) }
  def self.assignment_event_prefix(assignment_type)
    "enterprise_team.#{assignment_type}"
  end

  sig { void }
  private def check_sync_to_organizations
    error_message = "- Cannot sync to all GHAS enabled organizations if Enterprise Team has more than #{EnterpriseTeam.max_sync_members} members or Business has over #{EnterpriseTeam.max_sync_organizations} GHAS enabled organizations"
    errors.add(
      :sync_to_organizations,
      error_message,
    ) unless sync_to_organizations_was != "disabled" || sync_to_organizations == "disabled" || can_sync_to_organizations?
  end

  sig { void }
  private def strip_name
    return if name.nil?
    self.name = self.name.strip
  end

  sig { void }
  private def emit_unassignment_events
    self.enterprise_team_assignments.each do |assignment|
      assignment.emit_unassignment
    end
  end

  # Internal: Set a slug based on the Team's name.
  # Will set a unique slug scoped with the Business, to avoid clashes
  # between two teams with names like "ruby team" and "ruby-team".
  # This will set the slug if the name of the Team changes
  # or if the slug is nil (to handle legacy data).
  #
  # Returns the slug that was set, or nil if slug was not set
  sig { void }
  private def set_slug
    return if name.nil? || (!name_changed? && slug.present?)
    self.slug = generate_unique_slug
  end

  # Internal: generate unique slug for Business / Team combination
  sig { returns(String) }
  private def generate_unique_slug
    candidate = base = self.name.parameterize.to_s.presence || "team"

    index = 0
    while any_conflicting_slugs?(candidate)
      index += 1
      candidate = "#{base}-#{index}"
    end
    candidate
  end

  # Internal: Find conflicting slugs
  # Ignoring the current slug if the current Team exists
  sig { params(candidate: String).returns(T::Boolean) }
  private def any_conflicting_slugs?(candidate)
    scope = self.class.unscoped.where(business_id: business_id, slug: candidate)
    scope = scope.where("id <> ?", id) unless new_record?
    scope.any?
  end

  # Internal: Validates that a team's name and slug are unique by the team's
  # business. Why not just use `validates_uniqueness_of`? We have added a
  # boolean attribute to the teams table called `deleted`. It exists so that
  # users do not see teams they have just deleted but are still queued to be
  # deleted by us.
  #
  # So this check, essentially does what `validate_uniqueness_of` does but
  # ensures we are only checking against teams that have not been marked as
  # deleted.
  sig { void }
  private def name_and_slug_uniqueness_by_business
    EnterpriseTeam
      .owned_by(business)
      .active
      .where.not(id: id)
      .pluck(:name, :slug).each do |(existing_name, existing_slug)|
      errors.add :name, NAME_SLUG_UNIQUE_BY_BUSINESS_ERROR if existing_name.casecmp?(self.name) # case_insensitve
      errors.add :slug, NAME_SLUG_UNIQUE_BY_BUSINESS_ERROR if existing_slug == self.slug # case_sensitive
    end
  end
end
