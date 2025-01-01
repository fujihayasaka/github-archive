# typed: true
# frozen_string_literal: true

class ExternalGroup < ApplicationRecord::Domain::Users
  include Instrumentation::Model
  include BusinessesHelper

  VALID_PROVIDER_TYPES = %w(Organization::SamlProvider Business::SamlProvider Business::OIDCProvider)

  attr_readonly :guid

  belongs_to :provider, polymorphic: true
  delegate :target, to: :provider
  has_many :external_identity_group_memberships, dependent: :destroy
  has_many :external_group_teams, dependent: :destroy
  has_many :enterprise_team_group_mappings, dependent: :destroy
  has_many :enterprise_teams, through: :enterprise_team_group_mappings

  validates :provider, presence: true
  validates :provider_type, inclusion: VALID_PROVIDER_TYPES
  validates :external_id, presence: true
  validates :display_name, presence: true
  validates :display_name, length: { maximum: 128, too_long: "(SCIM: displayName) is too long (maximum is %{count} characters)." }, allow_blank: false
  validates :external_id, length: { maximum: 128, too_long: "id (SCIM: externalId) is too long (maximum is %{count} characters)." }, allow_blank: false
  validate :external_groups_enabled
  validate :valid_display_name_character_set

  before_validation :set_guid, on: :create

  after_update :set_provisioned_status_changed
  after_commit :remove_external_identity_group_memberships, on: :update

  # Public: Finds all external groups that are not marked as deleted.
  #
  # Returns a scope.
  scope :not_deleted, -> {
    where(deleted_at: nil)
  }


  # Public: Filters the ExternalGroup records whose display_name partially matches
  # the provided input. If the input is not present, returns all records.
  scope :display_name_filter, -> (input) {
    input.present? ? like_display_name(input) : all
  }

  # Public: Finds external groups which are for the given provider.
  #
  # provider  - An instance of the provider (e.g. Organization::SamlProvider)
  #
  # Returns a scope.
  scope :by_provider, -> (provider) {
    where(provider_id: provider.id, provider_type: provider.class.name)
  }

  scope :scim_filter, -> (filter) {
    # There is no difference how the query is executed, the difference is in the
    # parameter passed, therefore the science experiment is not needed here.
    SCIM::Filter.apply(filter, ExternalGroup, scope: all)
  }

  # Public: Finds the external groups matching an input string within a display_name
  #
  # input - The search string to match against display_name
  #
  # Returns a scope
  scope :like_display_name, -> (input) {
    where("external_groups.display_name LIKE ?", "%#{input}%")
  }

  # Public: Order by display name asc scope
  #
  # Returns a scope
  scope :order_by_display_name_asc, -> {
    order("display_name ASC")
  }

  # Public: Order by display name desc scope
  #
  # Returns a scope
  scope :order_by_display_name_desc, -> {
    order("display_name DESC")
  }

  # Public: Runs additional queries and preloads data for the SCIM API in enerprise environements.
  #   Leaving this one for enterprise environments, just in case the profile name is changed manually.
  #
  # Returns a scope
  scope :with_scim_preloads, -> {
    includes([
      { external_identity_group_memberships: { external_identity: :display_name_records } },
      { provider: :target }
    ])
  }

  # Public: Runs additional queries and preloads data for the SCIM API for EMUs
  #  One above also works but it is slower due to the number of records that it
  #  might have to retrive.
  #
  # Returns a scope
  scope :with_scim_preloads_emu, -> {
    includes([
      { external_identity_group_memberships: { external_identity: { user: :profile } } },
      { provider: :target }
    ])
  }

  # Public: Adds a condition that will check if the external group has any teams
  #
  # Returns a scope
  scope :with_teams, -> {
    where(<<-SQL)
      EXISTS (
        SELECT 1 FROM external_group_teams AS egt
        WHERE egt.external_group_id = external_groups.id
        LIMIT 1
      )
    SQL
  }

  # Public: Returns the SCIM group data we have.
  #
  # Returns a Platform::Provisioning::SCIMGroupData instance.
  def scim_group_data(include_members: true)
    scim_group_data = Platform::Provisioning::SCIMGroupData.new \
    [
      { "name" => "externalId", "value" => self.external_id },
      { "name" => "displayName", "value" => self.display_name },
      { "name" => "userName", "value" => self.display_name },
    ]

    if include_members
      self.external_identity_group_memberships.reload

      unless self.external_identity_group_memberships.empty?
        self.external_identity_group_memberships.each do |membership|
          scim_group_data.append "members",  membership.external_identity.guid
        end
      end
    end

    scim_group_data
  end

  # Public: Method to get external group identity memberships
  #
  # Returns Array of ExternalIdentityGroupMembership
  def members
    external_identity_group_memberships
  end

  # Mark an external group as deleted by adding deleted_at time
  def mark_group_deleted
    update(deleted_at: Time.now)
  end

  # Restore a deleted external group
  def restore_group
    update(deleted_at: nil)
  end

  def external_groups_enabled
    return unless provider && provider.target.present? && external_id && display_name

    return true if provider.enterprise_server_scim_enabled?

    unless provider.target.enterprise_managed_user_enabled?
      errors.add(:provider, "does not have emu mode enabled")
    end
  end

  def valid_display_name_character_set
    return if display_name.nil?

    if display_name.match(/[\u{10000}-\u{10FFFF}]/)
      errors.add(:display_name, "contains invalid 4-byte characters")
    end
  end

  def member?(identity_id)
    external_identity_group_memberships.pluck(:external_identity_id).include?(identity_id)
  end

  def set_guid
    self.guid = SimpleUUID::UUID.new.to_guid
  end

  def instrument_event(operation, team = nil, user: nil)
    if operation == :link || operation == :unlink
      payload = {
        operation: operation,
        external_group_id: id,
        external_group: display_name,
        external_group_external_id: external_id,
        provider_type: provider_type,
        team: team.name,
        team_id: team.id,
        scim_group_id: guid,
        org: team.organization
      }

      instrument operation, payload
    elsif operation == :add_member || operation == :remove_member
      instrument operation,
        operation: operation,
        external_group: display_name,
        external_group_id: id,
        external_group_external_id: external_id,
        provider_type: provider_type,
        user: user.display_login,
        user_id: user.id,
        scim_group_id: guid
    else
      instrument operation,
        operation: operation,
        external_group_id: id,
        external_group: display_name,
        external_group_external_id: external_id,
        provider_type: provider_type,
        scim_group_id: guid
    end
  end

  # Public: Returns an array of user ids of the users that are members
  # of the external group.
  #
  # Returns an array of user ids in integer.
  def member_user_ids
    external_identity_group_memberships.includes(:external_identity).pluck(:user_id)
  end

  # Public: Returns an array of user ids of the users that are not disabled members
  # of the external group.
  #
  # Returns an array of user ids in integer.
  def active_user_ids
    external_identity_group_memberships.joins(:external_identity)
      .where("external_identity.disabled_at": nil)
      .pluck("external_identity.user_id")
  end

  # Public: Returns true if a user is a member of the ExternalGroup and provisioned, false otherwise.
  #
  # Returns boolean.
  def active_user?(user_id)
    external_identity_group_memberships.joins(:external_identity)
      .where(external_identity: { disabled_at: nil, user_id: user_id })
      .present?
  end

  # Public: Returns true if the external group has any members that are guest collaborators, false otherwise.
  #
  # Returns boolean.
  def has_guest_collaborators?
    return false unless provider.target.enterprise_managed_user_enabled?

    members
      .joins(:external_identity)
      .where(external_identities: { guest_collaborator: true })
      .limit(1)
      .any?
  end

  def group_and_team_memberships_match?
    external_group_teams.not_in_sync.empty?
  end

  # Public: Returns a set of external group ids that contains guest collaborators.
  #
  # Returns set.
  def self.external_group_ids_with_guest_collaborator(external_group_ids)
    ExternalIdentityGroupMembership.
      joins(:external_group).
      joins(:external_identity).
      where(external_groups: { id: external_group_ids },
        external_identities: { guest_collaborator: true, disabled_at: nil, deleted_at: nil }).
      pluck(:external_group_id).
      to_set
  end

  private

  # Used to verify that the external group has been deleted
  attr_accessor :has_provisioned_status_changed

  def remove_external_identity_group_memberships
    if self.has_provisioned_status_changed
      begin
        ExternalGroupMemberReconcileJob.perform_later(external_group_id: self.id, caller: self.class.name)

        if enterprise_teams_enabled?(provider.business)
          GitHub.logger.info(
            "info.message" => "Queueing clear_enterprise_team_group_mappings_job",
            "gh.external_group.id" => self.id
          )
          ClearEnterpriseTeamGroupMappingsJob.perform_later(self.id)
        end
      ensure
        self.has_provisioned_status_changed = false
      end
    end
  end

  # Private: Sets has_provisioned_status_changed based on whether deleted_at or disabled_at has changed.
  #
  # Returns nothing
  def set_provisioned_status_changed
    self.has_provisioned_status_changed ||= saved_change_to_attribute?(:deleted_at)
  end
end
