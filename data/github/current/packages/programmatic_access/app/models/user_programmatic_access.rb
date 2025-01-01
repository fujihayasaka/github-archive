# typed: true
# frozen_string_literal: true

require "apps/k_v"

class UserProgrammaticAccess < ApplicationRecord::Permissions
  include GitHub::Validations
  include TokenExpirable
  include Instrumentation::Model
  include ProgrammaticAccess::AccessibleRepositoriesDependency
  include ProgrammaticAccess::ExpirationLimit
  include Integration::ConfigurationDependency
  include GitHub::FlipperActor
  include GitHub::VexiActor
  include LastAccessible

  MAX_LIMIT = 50
  NAME_MAX_LENGTH = 40
  DESCRIPTION_MAX_LENGTH = 1024

  CACHED_ATTRS_KEY_TEMPLATE = "user_programmatic_access_name_%s"
  CACHED_ATTRS_TTL = 12.hours

  belongs_to :bot, # rubocop:todo Rails/InverseOf
    class_name: "ProgrammaticAccessBot",
    foreign_key: :programmatic_access_bot_id,
    autosave: true,
    required: true

  belongs_to :owner, class_name: "User", foreign_key: :user_id, required: true # rubocop:todo Rails/InverseOf

  has_many :user_programmatic_access_grants
  destroy_dependents_in_background :user_programmatic_access_grants

  has_many :user_programmatic_access_grant_requests
  destroy_dependents_in_background :user_programmatic_access_grant_requests

  has_many :organization_programmatic_access_grants
  destroy_dependents_in_background :organization_programmatic_access_grants

  has_many :organization_programmatic_access_grant_requests
  destroy_dependents_in_background :organization_programmatic_access_grant_requests

  validates :description,
    allow_nil: true,
    allow_blank: false,
    unicode3: true,
    length: { maximum: DESCRIPTION_MAX_LENGTH }

  validates :name,
    presence: true,
    unicode3: true,
    length: { maximum: NAME_MAX_LENGTH },
    uniqueness: { scope: :owner }

  validate :restrict_name_with_token_prefix
  validate :restrict_description_with_token_prefix

  before_validation :generate_bot, on: :create
  before_validation :set_normalized_description, if: :will_save_change_to_description?
  after_validation :ensure_below_limit, on: :create

  before_update :set_previous_permissions

  before_destroy :set_grant_id
  before_destroy :cache_instrumentation_attributes

  after_update_commit :instrument_update

  after_destroy_commit :destroy_bot_async
  after_destroy_commit :instrument_deletion

  ACCESS_CUTOFF_DATE = Time.utc(2021, 8, 1)

  # Non persisted attributes just for compatibility with OauthAccess
  # Expiration time is persisted in Authnd alongside the token
  attribute :expires_at, :utc_timestamp
  attribute :issued_at, :utc_timestamp

  def self.notify_owner(about:, accesses:, owner:, target:, reason: nil)
    return unless accesses.any?

    case about
    when :revoked
      AccountMailer.programmatic_access_revoked_notice(accesses, owner, target).deliver_later
    when :request_approved
      AccountMailer.programmatic_access_approved_notice(accesses, owner, target).deliver_later
    when :request_denied
      AccountMailer.programmatic_access_denied_notice(accesses, owner, target, reason).deliver_later
    end

    :ok
  end

  # Public: Instrument creating records.
  #
  # Note, we're calling this from the controller and not
  # on an after_commit so we can pass in the token value
  #
  # Returns nothing.
  def instrument_creation(result)
    payload = grant_audit_log_attributes

    if (value = result&.value)
      pat = GitHub::Authentication::Attempt.new(token: result.value, from: :from)

      payload[:hashed_token] = Digest::SHA256.base64digest(value)
      payload[:programmatic_access_type] = pat.programmatic_access_type
      payload[:token_last_eight] = value.last(8)
      payload[:token_id] = id
    end

    instrument :create, payload

    GlobalInstrumenter.instrument "user_programmatic_access.create", {
      programmatic_access: self,
    }
  end

  # Public: Instrument updating records.
  #
  # payload - Hash of custom payload data.
  #
  # Returns nothing.
  def instrument_update(payload = {})
    if saved_changes.present?
      # the last key is an updated_at timestamp
      changes = saved_changes.keys[..-2].to_sentence
      return if changes == "accessed_at" # skip instrumentation of accessed_at bumps

      payload[:pat_field_changed] = changes
    end

    if grant.present?
      payload[:user_programmatic_access_grant_id] = grant.id
      payload[:repository_selection] = grant.repository_selection
      payload[:repository_count] = grant.repositories.count if grant.repository_selection == "subset"
      payload.merge!(permissions_changes)
    end

    payload[:token_id] = id

    unless payload.empty?
      instrument :update, payload
    end
  end

  # Public: Instrument regenerating the token.
  #
  # Note, we're calling this from the controller and not
  # on an after_commit so we can pass in the token value
  #
  # Returns nothing.
  def instrument_regeneration(result)
    payload = {}

    if (value = result&.value)
      payload[:token_last_eight] = value.last(8)
    end
    payload[:token_id] = id

    instrument :credential_regenerated, payload

    GlobalInstrumenter.instrument "user_programmatic_access.regenerate", {
      programmatic_access: self,
    }
  end

  # Public: Destroy access and instrument the deletion using
  # the provided explanation
  #
  # payload - Symbol of the explanation for deletion. All valid Symbols can be
  # found in OauthUtil::VALID_DESTROY_EXPLANATIONS. These symbols are mapped
  # to a more descriptive explanation that will be shown in the audit log.
  #
  # Returns the result of calling destroy() on the model instance.
  def destroy_with_explanation(explanation)
    unless OauthUtil.destroy_explanation(explanation)
      raise ArgumentError, "invalid destroy explanation: #{explanation}"
    end
    @destroy_explanation = explanation
    destroy
  end

  # Public: Instrument deleting records.
  #
  # payload - Hash of custom payload data.
  #
  # Returns nothing.
  def instrument_deletion(payload = {})
    if event_actor&.employee? && event_actor != owner
      actor_hash = GitHub.guarded_audit_log_staff_actor_entry(event_actor)
      payload = payload.merge(actor_hash)
    end

    payload[:user_programmatic_access_grant_id] = @grant_id if @grant_id
    payload[:token_id] = id

    instrument :destroy, payload.merge(
      explanation: @destroy_explanation,
    )
  end

  # Public: Instrument revoking records.
  #
  # payload - Hash of custom payload data.
  #
  # Returns nothing
  def instrument_credential_revoke(payload = {})
    instrument :credential_revoked, payload
  end

  # Public: Instrument expiring records.
  #
  # payload - Hash of custom payload data.
  #
  # Returns nothing
  def instrument_credential_expire(payload = {})
    instrument :credential_expired, payload
  end

  def notify_owner(about:, details: nil)
    return unless ProgrammaticAccess.owner_can_be_notified?(self, event_type: about)

    case about
    when :created
      AccountMailer.programmatic_access_created_notice(self).deliver_later
    when :regenerated
      AccountMailer.programmatic_access_regenerated_notice(self).deliver_later
    when :expiration_warning
      AccountMailer.programmatic_access_expiration_warning_notice(self, details).deliver_later
    when :expired
      AccountMailer.programmatic_access_expired_notice(self).deliver_later
    end

    :ok
  end

  # The user who performed the action as set in the GitHub request context. If the context doesn't
  # contain an actor, fallback to the user that the oauth authorization belongs to.
  def event_actor
    return @event_actor if defined?(@event_actor)
    @event_actor = (User.find_by(id: GitHub.context[:actor_id]) || owner)
  end

  def event_payload
    {
      user_programmatic_access_id: id,
      token_id: id,
      user_programmatic_access_name: name,
      user: owner&.login,
      user_id: user_id,
    }
  end

  def event_prefix
    "personal_access_token"
  end

  # Public: Returns the single grant associated with this access.
  #
  # Currently, user_programmatic_accesses can be associated with one
  # and only one grant.
  def grant
    user_programmatic_access_grants.first || organization_programmatic_access_grants.first
  end

  def grant_request
    organization_programmatic_access_grant_requests.first
  end

  def targeting_organizations?
    organization_programmatic_access_grants.exists? || organization_programmatic_access_grant_requests.exists?
  end

  # Public: Returns the grant associated with a given target.
  #
  # Returns either a UserProgrammaticAccessGrant,
  # OrganizationProgrammaticAccessGrant or nil.
  def grant_for(target)
    grant_for_scope(target).first
  end

  def grant_for?(target)
    grant_for_scope(target).exists?
  end

  def grant_for_repository(repository)
    return unless repository

    grant = grant_for(repository.owner)
    return unless grant

    args = { repository_ids: [repository.id] }

    if Repositories::Public.organization_owned?(repository)
      args[:organization] = repository.owner
    end

    grant.repository_ids(**args).any? ? grant : nil
  end

  def grant_for_repository?(repository)
    grant_for_repository(repository).present?
  end

  def previous_permissions
    @previous_permissions || {}
  end

  def has_requested_grant?
    organization_programmatic_access_grant_requests.exists?
  end

  def active_request_or_grant
    grant_request || grant
  end

  def target_for_conditional_access
    owner
  end

  def pat_type
    ProgrammaticAccessTokenType::FineGrained
  end

  def pat_type_name
    pat_type.name
  end

  private

  def generate_bot
    build_bot
    T.must(bot).slug = SecureRandom.hex(17)
  end

  def grant_for_scope(target)
    if target.try(:user?)
      self.user_programmatic_access_grants.where(target: target)
    elsif target.try(:organization?)
      self.organization_programmatic_access_grants.where(target: target)
    else
      UserProgrammaticAccessGrant.none
    end
  end

  def set_normalized_description
    self.description = description.presence
  end

  def set_previous_permissions
    @previous_permissions = (grant&.permissions || {})
  end

  def set_grant_id
    @grant_id = grant&.id
  end

  def cache_instrumentation_attributes
    attrs = { name:, owner_name: owner&.login, owner_id: owner&.id }

    Apps::KV.store.set(
      CACHED_ATTRS_KEY_TEMPLATE % id,
      attrs.to_json,
      expires: CACHED_ATTRS_TTL.from_now
    )
  end

  def permissions_changes
    differ = PermissionsDiffer.new(
      previous_permissions: previous_permissions,
      new_permissions: grant.permissions,
    )

    {
      permissions_added:      differ.added_permissions,
      permissions_downgraded: differ.downgraded_permissions,
      permissions_removed:    differ.removed_permissions,
      permissions_unchanged:  differ.unchanged_permissions,
      permissions_upgraded:   differ.upgraded_permissions,
    }.delete_if { |_, v| v.empty? }
  end

  def ensure_below_limit
    return true unless self.owner
    return true if UserProgrammaticAccess.where(owner: self.owner).count < MAX_LIMIT

    errors.add(:owner, :too_many, message: "cannot have more than #{MAX_LIMIT} #{'token'.pluralize(MAX_LIMIT)}")
  end

  def destroy_bot_async
    bot&.async_destroy
  end

  def grant_audit_log_attributes
    payload = {}

    granted = self.active_request_or_grant
    return payload unless granted

    if granted.target.organization?
      payload[:org]    = granted.target.display_login
      payload[:org_id] = granted.organization_id
    end

    # Ensure that all grant type records created have their primary ids logged.
    [grant, grant_request].each do |grantable|
      next unless grantable

      # example -> :organization_programmatic_access_grant_id
      payload[:"#{grantable.class.name.underscore}_id"] = grantable.id
    end

    case granted
    when OrganizationProgrammaticAccessGrantRequest
      payload[:access_requested] = true
      payload[:reason] = granted.reason
      payload[:permissions_requested] = granted.permissions
    else
      payload[:permissions_added] = granted.permissions
    end

    payload[:repository_selection] = granted.repository_selection

    if granted.repository_selection == "subset"
      payload[:repository_count] = granted.repositories.count
    end

    payload
  end

  def restrict_name_with_token_prefix
    return unless name.present?

    if ProgrammaticAccessTokens::Domain::TOKEN_PREFIXES.match?(name)
      errors.add :name, "can't include GitHub token prefix"
    end
  end

  def restrict_description_with_token_prefix
    return unless description.present?

    if ProgrammaticAccessTokens::Domain::TOKEN_PREFIXES.match?(description)
      errors.add :description, "can't include GitHub token prefix"
    end
  end
end
