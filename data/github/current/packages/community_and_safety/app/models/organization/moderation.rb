# typed: true
# frozen_string_literal: true

class Organization::Moderation
  include Ability::Subject
  include Ability::Membership
  include Instrumentation::Model

  MODERATOR_LIMIT = 10

  attr_reader :organization

  def initialize(organization)
    @organization = organization
  end

  # Public: Indicates if a specified User or Team is a moderator.
  #
  # moderator – The User or Team to check.
  #
  # Returns a Boolean.
  def moderator?(moderator)
    return false unless GitHub.organization_moderators_enabled?
    permit?(moderator, :write)
  end

  # Public: Indicates if a specified User or Team is a moderator.
  #
  # moderator – The User or Team to check.
  #
  # Returns a Promise<Boolean>.
  def async_moderator?(moderator)
    return Promise.resolve(false) unless GitHub.organization_moderators_enabled?
    async_permit?(moderator, :write)
  end

  # Public: Adds a moderator to an organization.
  #
  # moderator - The User or Team to add as a moderator. The User or Team must
  #             belong to the organization.
  # actor     - The User who is adding the moderator for this organization. Must
  #             be an owner of the organization.
  #
  # Returns an OperationResult.
  def add_moderator(moderator, actor:)
    unless GitHub.organization_moderators_enabled?
      return OperationResult.failure(
        moderator: moderator,
        errors: ["Moderators are not available in this GitHub environment"],
      )
    end

    unless organization.adminable_by?(actor)
      return OperationResult.failure(
        moderator: moderator,
        errors: ["Actor is not authorized to manage moderators"],
      )
    end

    unless eligible_moderator?(moderator)
      return OperationResult.failure(
        moderator: moderator,
        errors: ["#{moderator.class} must be a member of the organization"],
      )
    end

    if moderators.count >= MODERATOR_LIMIT
      return OperationResult.failure(
        moderator: moderator,
        errors: ["You can only have a maximum of #{MODERATOR_LIMIT} users or teams as moderators"],
      )
    end

    grant(moderator, :write, grantor: actor)
    instrument_for(action: :add, moderator: moderator, actor: actor)
    OperationResult.success(moderator: moderator)
  end

  # Public: Removes a moderator for an organization.
  #
  # moderator - The User or Team to remove as a moderator.
  # actor     - The User who is removing the moderator for this organization. Must
  #             be an owner of the organization.
  # force     - A Boolean indicating if we should remove the moderator even if
  #             the actor is not authorized to manage moderators.
  #
  # Returns an OperationResult.
  def remove_moderator(moderator, actor:, force: false)
    unless GitHub.organization_moderators_enabled?
      return OperationResult.failure(
        moderator: moderator,
        errors: ["Moderators are not available in this GitHub environment"],
      )
    end

    unless force || organization.adminable_by?(actor)
      return OperationResult.failure(
        moderator: moderator,
        errors: ["Actor is not authorized to manage moderators"],
      )
    end

    return OperationResult.success(moderator: moderator) unless moderator?(moderator)

    revoke(moderator)
    instrument_for(action: :remove, moderator: moderator, actor: actor)
    OperationResult.success(moderator: moderator)
  end

  # Public: Removes all User moderators from this organization. This is used
  #         when an organization is deleted.
  #         WARNING: THIS DOES NOT REMOVE ABILITIES FROM TEAMS.
  #
  # Returns a Boolean.
  def remove_all_user_moderators
    members.each do |moderator|
      remove_moderator(moderator, actor: nil, force: true)
    end

    true
  end

  # Public: Get a list of all moderators for an organization.
  #
  # Returns an Array[User|Team].
  def moderators
    return [] unless GitHub.organization_moderators_enabled?

    team_ids = Ability.where(
      subject_type: self.class,
      subject_id: ability_id,
      actor_type: Team,
      priority: Ability.priorities[:direct],
    ).pluck(:actor_id)

    teams = Team.where(id: team_ids)
    users = User.where(id: member_ids)

    teams + users
  end

  def ability_id
    organization.id
  end

  def target_for_conditional_access
    organization
  end

  def event_prefix
    :organization_moderators
  end

  class OperationResult
    attr_reader :moderator, :success, :errors
    alias_method :success?, :success

    # moderator - the User that is being added/removed as a moderator.
    # success   – a Boolean indicating the success of an operation.
    # errors    – an Array of String error messages.
    def initialize(moderator:, success:, errors:)
      @moderator = moderator
      @success   = success
      @errors    = errors
    end

    def self.success(moderator:)
      new(success: true, moderator: moderator, errors: [])
    end

    def self.failure(moderator:, errors:)
      new(success: false, moderator: moderator, errors: errors)
    end
  end

  private

  # Private: Indicates if a User or Team is eligible to be a moderator for the
  #          organization.
  #
  # moderator – The User or Team to check.
  #
  # Returns a Boolean.
  def eligible_moderator?(moderator)
    if moderator.is_a?(Team)
      moderator.organization_id == organization.id
    else
      organization.member?(moderator)
    end
  end

  # Private: Instrument an audit log event when adding/removing moderators.
  #
  # action    - A Symbol action, either :add or :remove.
  # moderator - A User or Team that is being added/removed as a moderator.
  # actor     - A User actor who is adding/removing a moderator.
  #
  # Returns nothing.
  def instrument_for(action:, moderator:, actor:)
    moderator_type = moderator.class.to_s.downcase
    action_name = "#{action}_#{moderator_type}"
    payload = { actor: actor }.merge(moderator.event_context).merge(organization.event_context)
    instrument action_name, payload

    GlobalInstrumenter.instrument("organization_moderators.moderator_update", {
      organization: organization,
      action: action == :add ? "ADDED" : "REMOVED",
      moderator_type: moderator.class.to_s,
      moderator_id: moderator.id,
      actor: actor,
    })
  end
end
