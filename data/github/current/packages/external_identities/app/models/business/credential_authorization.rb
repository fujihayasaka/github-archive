# typed: true
# frozen_string_literal: true

#
# This model tracks whether a credential has been granted access to a
# business (enterprise). A credential can be a personal access token or an oauth access
# token (both modeled by OauthAccess). It can be expanded to include other
# models such as public keys.
#
# Similar to Organization::CredentialAuthorization but at the enterprise scope.
class Business::CredentialAuthorization < ApplicationRecord::Domain::Users
  include Instrumentation::Model
  include GitHub::Relay::GlobalIdentification

  def event_prefix
    :business_credential_authorization
  end

  def event_payload
    {
      business: business,
      credential_id: credential_id,
      credential_type: credential_type,
      actor_type: actor_type,
    }.tap do |p|
      if actor.is_a?(User)
        p[:actor] = actor
      else
        p[actor.event_prefix] = actor if actor
      end

      if using_public_key?
        p[:fingerprint] = fingerprint
      else
        if using_application_token?
          p[:oauth_credential_type] = "OauthAccess"
        elsif using_personal_access_token?
          p[:oauth_credential_type] = "Personal Access Token"
        end

        # Check the audit contexts to make sure this action isn't being done programmatically
        # We want to prioritize maintaining data about token usage in the audit log
        if Audit.context[:token_id].nil?
          p[:oauth_access_id] = credential_id
          p[:token_id] = credential_id
          p[:oauth_scopes] = credential&.scopes_string
          p[:token_scopes] = credential&.scopes_string
          p[:hashed_token] = credential&.hashed_token
        else
          p[:managed_oauth_access_id] = credential_id
          p[:managed_token_id] = credential_id
          p[:managed_oauth_scopes] = credential&.scopes_string
          p[:managed_token_scopes] = credential&.scopes_string
          p[:managed_hashed_token] = credential&.hashed_token
        end
      end
    end
  end

  self.table_name = :business_credential_authorizations

  belongs_to :business
  belongs_to :credential, polymorphic: true
  belongs_to :actor, polymorphic: true
  belongs_to :revoked_by, class_name: "User"

  validates :actor, presence: true
  validates :business, presence: true
  validates :credential, presence: true

  validates :credential_id, uniqueness: { scope: [:credential_type, :business_id, :actor_id, :actor_type] }

  # Initially supporting only PATs as per requirements
  validates :credential_type, inclusion: { in: %w[OauthAccess], message: "must be an OauthAccess" }
  validate :validate_actor_is_member_of_business, unless: [:revoked?, :using_application_token?]
  validate :validate_actor_is_enterprise_managed, unless: [:revoked?, :using_application_token?]
  validate :validate_credential_is_owned_by_actor, unless: :using_application_token?
  validate :validate_credential_is_not_revoked, if: :using_public_key?

  before_create :set_is_application_value
  before_validation :set_fingerprint_sha256
  after_create_commit :instrument_grant
  after_destroy_commit :instrument_deauthorization

  scope :by_credential, -> (credential:) {
    fail "`credential` must not be a relation (cross-domain risk)" if credential.is_a?(ActiveRecord::Relation)
    where(credential: credential)
  }

  scope :by_business, -> (business:) {
    if business.is_a?(Array)
      where(business_id: business.map(&:id))
    else
      where(business_id: business.id)
    end
  }

  scope :by_actor, -> (actor:) {
    where(actor_id: actor.id, actor_type: actor.class.name)
  }

  scope :by_business_credential, -> (business:, credential:) {
    by_business(business: business).
    by_credential(credential: credential)
  }

  scope :active, -> {
    where("revoked_by_id IS NULL")
  }

  scope :revoked, -> {
    where("revoked_by_id IS NOT NULL")
  }

  scope :public_key_credentials_by_fingerprint, -> (fingerprint_sha256:) {
    where(credential_type: "PublicKey", fingerprint_sha256: fingerprint_sha256)
  }

  scope :excluding_applications, -> {
    where(is_application: false)
  }

  def self.grant(business:, credential:, actor:)
    authorization = active.by_business_credential(business: business, credential: credential).first

    if authorization.nil?
      authorization = create(business: business, credential: credential, actor: actor)
      return nil unless authorization.persisted?
    end

    authorization
  end

  def self.revoke(business:, credential:, actor:)
    # Business admins can revoke any authorized credentials on the business
    can_revoke = business.actor_can_write_sso?(actor)

    # Personal access tokens can be revoked by its owner
    can_revoke ||= (credential.personal_access_token? && credential.user == actor)

    return unless can_revoke

    if authorization = authorization(business: business, credential: credential)
      authorization.update(revoked_by_id: actor.id, revoked_at: Time.now)
      authorization.instrument :revoke, actor: actor, owner: authorization.actor
      authorization
    end
  end

  def self.authorization(business:, credential:)
    return unless credential.present?

    active.by_business_credential(business: business, credential: credential).first
  end

  # Public: whether or not this credential's authorization was revoked by a
  # business administrator.
  #
  # Returns true if the authorization was revoked, false if not.
  def revoked?
    revoked_by_id.present?
  end

  # Public: whether or not this credential's authorization is active.
  #
  # Returns true if the authorization is active, false if not.
  def active?
    !revoked?
  end

  # Public: whether or not the credential is a token generated for use by an
  # OAuth Application.
  #
  # Returns true if `credential` is an application token, or false if it is a
  # personal access token or other type of object.
  def using_application_token?
    credential.is_a?(OauthAccess) && !credential.personal_access_token?
  end

  # Public: whether or not the credential is a token generated for use by an
  # Personal Access Token.
  #
  # Returns true if `credential` is a personal access token, or false if it is a
  # application token or other type of object.
  def using_personal_access_token?
    credential.is_a?(OauthAccess) && credential.personal_access_token?
  end

  # Public: whether or not the credential is an token generated for use by an
  # SSH key.
  #
  # Returns true if `credential` is a token for SSH key, or false if it is a
  # personal access token or other type of object.
  def using_public_key?
    credential_type == "PublicKey"
  end

  # Public: returns the last time the underlying credential was accessed
  #
  # Returns a ActiveSupport::TimeWithZone corresponding to the last time the credential was accessed
  # may be nil if the credential was never accessed
  def accessed_at
    credential&.last_access_time
  end

  # Public: returns the fingerprint in the format of ssh-keygen
  #
  # Returns the fingerprint in a format suitable to return to users in the UI or API.
  def fingerprint
    if GitHub.multi_tenant_enterprise?
      "SHA256:#{fingerprint_sha256.split("_")[0]}"
    else
      "SHA256:#{fingerprint_sha256}"
    end
  end

  # Internal: This method sets the de-normalized is_application value based on the credential
  #
  # Returns nothing
  def set_is_application_value
    # Because we can't join against the oauth_accesses table we have to de-normalize the value here in order to speed up queries
    return unless credential_type == "OauthAccess"

    self.is_application = credential&.application_id != 0
  end

  def instrument_grant
    GitHub.dogstats.increment("business_credential_authorization", tags: ["action:grant"])
    instrument :grant
  end

  # Public: Sets the fingerprint SHA256 based on the credential
  #
  # Returns nothing
  def set_fingerprint_sha256
    if using_public_key?
      self.fingerprint_sha256 = credential.fingerprint_sha256
    end
  end

  private

  def instrument_deauthorization
    GitHub.dogstats.increment("business_credential_authorization", tags: ["action:deauthorize"])
    instrument :deauthorize
  end

  def validate_actor_is_member_of_business
    return unless actor && business

    unless business&.unaffiliated_member?(actor)
      errors.add(:actor, "must be a member of the business")
    end
  end

  def validate_actor_is_enterprise_managed
    return unless actor

    unless actor.is_enterprise_managed?
      errors.add(:actor, "must be enterprise managed")
    end
  end

  def validate_credential_is_owned_by_actor
    return unless actor && credential

    if actor != credential.user
      errors.add(:credential, "must be owned by actor")
    end
  end

  def validate_credential_is_not_revoked
    if self.class.by_business(business: business).revoked.where(fingerprint_sha256: credential.fingerprint_sha256).any?
      errors.add(:credential, "has been revoked")
    end
  end
end
