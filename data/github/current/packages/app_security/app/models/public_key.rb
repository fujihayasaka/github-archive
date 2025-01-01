# typed: true
# frozen_string_literal: true

class PublicKey < ApplicationRecord::Domain::Users
  extend T::Sig

  module CreationExtension
    extend T::Helpers

    requires_ancestor { PublicKey }

    # Public: Create a verified public key, belonging to the association owner
    # (e.g., the User or Repository).
    #
    # attributes - The Hash of attributes used to construct the key.
    #              :key                 - The String public key value.
    #              :verifier            - The User that verified the key.
    #              :title               - The String title for the key (optional).
    #              :oauth_authorization - The OauthAuthorization that initiated
    #                                     the request
    #              :read_only           - The Boolean value indicating whether
    #                                     this key can only be used for reading.
    #
    # Examples
    #
    #   # Reference the extension when setting up the association
    #   class Repository < ApplicationRecord::Domain::Repositories
    #     has_many :public_keys, :extend => PublicKey::CreationExtension
    #   end
    #
    #   # Put it to use
    #   repo_instance.public_keys.create_with_verification \
    #     :key => 'ssh-rsa AAAAB...',
    #     :verifier => current_user
    #
    # Returns the new PublicKey. Callers can invoke #new_record? on the
    #   PublicKey to determine if the key was successfully persisted.
    def create_with_verification(attributes = {})
      T.bind(self, ActiveRecord::Associations::CollectionProxy)

      public_key = build(
        key: attributes[:key],
        title: attributes[:title],
        read_only: attributes[:read_only] == true,
      )

      if authorization = attributes[:oauth_authorization]
        public_key.oauth_authorization = authorization

        # set oauth app foreign key for more efficient database join queries
        if authorization.oauth_application_authorization?
          public_key.oauth_application_id = authorization.application_id
        end
      end

      public_key.verify(attributes[:verifier])
      public_key
    end
  end


  # MIN_KEY_BIT_LENGTH is used by the PublicKey::SharedValidations module,
  # and differs between GitSigningSshPublicKey and PublicKey
  # We have [an issue](https://github.com/github/pse-architecture/issues/652)
  # to raise this number to 2047 for PublicKey in the future.
  MIN_KEY_BIT_LENGTH = 1023

  # required because sorbet does not permit dynamic constant references (5001)
  def self.min_key_bit_length
    MIN_KEY_BIT_LENGTH
  end

  include PublicKey::SharedValidations

  belongs_to :user
  belongs_to :repository
  destroy_in_background_with :repository
  belongs_to :creator,  class_name: "User"
  belongs_to :verifier, class_name: "User"
  belongs_to :oauth_authorization

  has_many :active_org_credential_authorizations,
    -> { Organization::CredentialAuthorization.active },
    class_name: "Organization::CredentialAuthorization",
    as: :credential,
    inverse_of: :credential,
    foreign_key: "credential_id",
    dependent: :destroy

  has_many :two_factor_recovery_requests

  before_save       :set_fingerprint_sha256, :set_defaults

  # NOTE: set_title must run before strip_comments since it extracts the title
  # from the comments.
  before_validation :strip_whitespace, :set_title, :strip_prefix, :strip_comments
  before_validation :set_created_by, on: :create

  after_create :link_revoked_organization_credential_authorization
  after_create_commit :instrument_creation
  after_update_commit :instrument_update, unless: :saved_change_to_unverification_reason?
  before_destroy :generate_webhook_payload
  after_commit :instrument_deletion, :queue_webhook_delivery, on: :destroy

  after_commit  :notify_creation, on: :create

  validate :user_or_repository_assigned
  validate :consistency_between_created_by_and_oauth_authorization_id
  validate :only_read_only_if_repo_key
  validate :auth_key_is_not_someone_elses_signing_key
  validates_inclusion_of :created_by, in: %w(user oauth_access unknown)

  after_destroy :destroy_oauth_authorization, if: :oauth_authorization

  extend GitHub::Encoding
  force_utf8_encoding :fingerprint_sha256, :key

  VALID_UNVERIFY_REASONS = {
    # Whenever a GitHub Employee is hired, we revoke their OAuth applications
    # and SSH keys so that 3rd parties don't inadvertently get access to GitHub code.
    new_hire: "unverified upon becoming a GitHub employee",

    # Keys are automatically unverified if they have not been used since
    # GitHub::Transitions::UnverifyStaleSshKeys::FreshUntil.ago
    stale: "unverified due to lack of use",

    # Keys are automatically unverified if we find the corresponding unencrypted
    # private key in a public repository.
    token_scan: "unverified automatically (private key found in a public repository)",

    # Keys are unverified by a user explicitly if we find the corresponding unencrypted
    # private key in a private repository.
    token_scan_revoked_by_user_in_private_repo: "unverified by a user (private key found in a private repository)",

    # Keys are automatically unverified if we find the corresponding unencrypted
    # private key in a public repository.
    site_admin: "unverified by #{GitHub.host_name} administrator",
  }.freeze

  VALID_DESTROY_REASONS = {
    # Keys are automatically unverified if they have not been used
    # in over a year
    stale: "unverified due to lack of use",

    # Keys which have been manually removed by the user
    removed_by_user: "Deleted by the user",

    # Keys that have been removed by GitHub Staff
    removed_by_staff: "Deleted by GitHub",

    user_deprovisioned: "Deleted due to user deprovisioning"
  }.freeze

  DEFAULT_UNVERIFICATION_REASON = "legacy key automatically unverified".freeze

  def self.unverification_explanation(reason)
    VALID_UNVERIFY_REASONS[reason.try(:to_sym)] || DEFAULT_UNVERIFICATION_REASON
  end

  def self.destroy_explanation(reason)
    VALID_DESTROY_REASONS[reason.try(:to_sym)]
  end

  # Public: Scopes a query to public keys in repositories for which the
  # given User or Organization sets the access policy.
  #
  # user_or_org - User or Organization instance, or Integer record ID
  #
  # Returns an array of `Repository` ids
  def self.repository_ids_for_policymaker(policymaker)
    Repository.connection.select_values(Arel.sql(<<-SQL, policymaker_id: policymaker.id))
      SELECT repositories.id
      FROM repositories
      WHERE repositories.public = 1 AND repositories.owner_id = :policymaker_id

      UNION

      SELECT repositories.id
      FROM repositories
      INNER JOIN repository_networks
        ON repository_networks.id = repositories.source_id
      INNER JOIN repositories network_roots
        ON network_roots.id = repository_networks.root_id
      WHERE repositories.public = 0 AND network_roots.owner_id = :policymaker_id
    SQL
  end

  # Public: Scopes a query to public keys created by a particular
  # OAuth Application
  #
  # app_id - OauthApplication instance, or Integer record ID
  #
  # Returns an ActiveRecord::NamedScope::Scope
  def self.created_by_application(oauth_app)
    app_id = case oauth_app
    when Integer then oauth_app
    when OauthApplication then oauth_app.id
    end

    raise ArgumentError, "OAuthApplication is required" if app_id.nil?

    joins(:oauth_authorization).where("oauth_authorizations.application_id" => app_id)
  end

  # Public: Scopes a query to public keys that are verified
  #
  # Returns an ActiveRecord::Relation
  def self.verified
    where("verified_at IS NOT NULL")
  end

  # Public: Scopes a query to public keys that are NOT verified
  #
  # Returns an ActiveRecord::Relation
  def self.unverified
    where("verified_at IS NULL")
  end

  # Public: Scopes a query to public keys accessed since a certain time
  #
  # time = the Time to query keys accessed since
  #
  # Returns an ActiveRecord::Relation
  def self.accessed_since(time)
    where(["accessed_at >= (?)", time])
  end

  # Public: Scopes a query to public keys used since a certain time
  #
  # order     = 'accessed' optional, defaults to order by 'created_at'
  # direction = 'asc' or 'desc' optional, defaults to 'desc'
  #
  # Returns an ActiveRecord::Relation
  def self.sorted_by(order = "created", direction)
    case order
    when /accessed/
      order = "accessed_at"
    else
      order = "created_at"
    end

    order += (direction == "asc" ? " ASC" : " DESC")
    order(order)
  end

  # Public: Scopes a query to public keys based on the fingerprint
  def self.with_fingerprint(fingerprint)
    if GitHub.multi_tenant_enterprise? && (current_tenant = GitHub::CurrentTenant.get)
      fingerprint_with_shortcode = fingerprint << "_#{current_tenant.shortcode}"
      where(fingerprint_sha256: fingerprint_with_shortcode.delete_prefix("SHA256:"))
    else
      where(fingerprint_sha256: fingerprint.delete_prefix("SHA256:"))
    end
  end

  def user_has_email
    return if GitHub.enterprise? || repository

    if user && ApplicationMailer::Helpers.user_email(user).blank?
      errors.add :base, "To be extra safe, please add an email address to your account before creating a public key."
    end
  end

  def to_s
    key
  end

  def ==(other)
    to_s == other.to_s
  end

  def title
    self[:title].blank? && key ? key[0..25] : self[:title]
  end

  # Public: Returns true if the key has been verified (and a timestamp has been
  # set). LDAP synced keys are verified during the sync process.
  def verified?
    !verified_at.nil?
  end

  # Public: Returns true if the key is verified, or if the actor owns the key.
  def readable_by?(actor)
    verified? || user == actor
  end

  def can_verify_account_ownership?
    return false unless verified?
    return false unless oauth_authorization.nil? || Apps::Internal.capable?(:verify_account_ownership, app: oauth_application)
    true
  end

  def verify(verifier)
    self.created_by = "user" if created_by_unknown?

    unless self.verified?
      self.unverification_reason = nil
      self.creator ||= verifier
      self.verifier = verifier
      self.verified_at = Time.current
    end

    if save_result = self.save
      GitHub.dogstats.increment("public_key", tags: ["action:verify", "valid:true"])
      instrument :verify
    else
      GitHub.dogstats.increment("public_key", tags: ["action:verify", "valid:false"])
      instrument :verification_failure, reason: "key #{errors[:key].join(', ')}"
    end

    save_result
  end

  def unverification_explanation
    self.class.unverification_explanation(unverification_reason)
  end

  def unverify(explanation_key)
    unless VALID_UNVERIFY_REASONS.key?(explanation_key)
      fail ArgumentError, "invalid unverify reason: #{explanation_key}"
    end

    self.verifier = nil
    self.verified_at = nil
    self.unverification_reason = explanation_key
    if self.save
      GitHub.dogstats.increment("public_key", tags: ["action:unverify", "valid:true", "explanation:#{explanation_key}"])
      instrument :unverify, explanation: explanation_key
    else
      GitHub.dogstats.increment("public_key", tags: ["action:unverify", "valid:false", "explanation:#{explanation_key}"])
      instrument :unverification_failure, reason: "key #{errors[:key].join(', ')}"
    end
  end

  # Public: Returns true if we are sure that the key was created by the user
  # directly or via a personal access token. Returns false otherwise.
  #
  # Keys created prior to github/github##20015 are of "unknown origin." We don't
  # know whether those keys were created by the user or by an OAuth app that the
  # user authorized. This method returns false for those keys.
  #
  # As the name implies, personal access tokens are *personal*. Using one to
  # create a key implies that the user is directly responsible for the creation
  # of the key.
  #
  # Returns a Boolean.
  def created_by_user?
    created_by == "user" || created_by_personal_access_token?
  end

  def deploy_key?
    !!repository
  end

  # Public: Returns true if the key was created by an OAuth application. Returns
  # false if the key was created by a personal access token, or if the key was
  # not created via OAuth.
  #
  # Returns a Boolean.
  def created_by_oauth_application?
    oauth_authorization && !T.must(oauth_authorization).personal_access_authorization?
  end

  # Public: Returns true if the key was created by a personal access token.
  # Returns false otherwise.
  #
  # Returns a Boolean.
  def created_by_personal_access_token?
    oauth_authorization && T.must(oauth_authorization).personal_access_authorization?
  end

  # Public: Returns true if the key was created by an oauth application and has
  # access to some of the given scopes.
  # Returns false otherwise.
  #
  # Returns a Boolean.
  def oauth_access?(*scopes)
    oauth_authorization && scopes.any? { |scope| T.must(oauth_authorization).scopes.include?(scope.to_s) }
  end

  # Public: Returns true if the key is of unknown origin. (All keys created
  # prior to github/github##20015 are of unknown origin. We don't know whether
  # those keys were created by the user or by an OAuth app that the user
  # authorized.)
  #
  # Returns a Boolean.
  def created_by_unknown?
    created_by == "unknown"
  end

  # Public: Returns the OAuth application (if any) that created this key.
  #
  # Returns an OauthApplication or nil.
  def oauth_application
    return nil unless created_by_oauth_application?

    T.must(oauth_authorization).application
  end

  # Public: Determine whether the given user is authorized to administer this
  # key.
  #
  # Returns a Boolean.
  def adminable_by?(user)
    user == self.owner || user.deploy_keys.include?(self)
  end

  # Public: The user or organization that owns this key. For deploy keys, we
  # consider the repository's owner to be the key's owner.
  #
  # Returns a User or Organization.
  def owner
    if repository
      T.must(repository).owner
    else
      user
    end
  end

  # Is this a repo key?
  #
  # Returns boolean.
  def repository_key?
    self.repository.present?
  end

  def key_type
    @key_type ||= key.split[0]
  end

  # Internal: Participates in abilities on behalf of this model.
  def ability_delegate
    owner
  end

  protected

  def notify_user_key_action_via_email?
    self.user && ApplicationMailer::Helpers.user_email(self.user).present?
  end

  def set_created_by
    self.created_by = oauth_authorization ? "oauth_access" : "user"
  end

  def set_defaults
    self.username = "git"
  end

  # Prevents users deleting and adding their public keys to get around
  # organizations that have revoked their credentials.
  def link_revoked_organization_credential_authorization
    Organization::CredentialAuthorization\
      .public_key_credentials_by_fingerprint(fingerprint_sha256: fingerprint_sha256)\
      .revoked.update_all(credential_id: id)
  end

  def user_or_repository_assigned
    if self.user.nil? && self.repository.nil?
      errors.add :base, "one of either user_id or repository_id must be assigned"
    elsif self.user_id && self.repository_id
      errors.add :base, "only one of user_id or repository_id can be assigned"
    elsif self.user && !T.must(self.user).user?
      errors.add :user, "invalid user"
    end
  end

  def consistency_between_created_by_and_oauth_authorization_id
    if oauth_authorization.nil? && created_by == "oauth_access"
      errors.add :oauth_authorization,
        "can't be blank when created_by is 'oauth_access'"
    elsif oauth_authorization.present? && created_by != "oauth_access"
      errors.add :created_by,
        "must be 'oauth_access' when oauth_access is present"
    end
  end

  # Validation checking that only repo keys are marked as read-only.
  #
  # Returns boolean.
  def only_read_only_if_repo_key
    if read_only? && !repository_key?
      errors.add :base, "only repository keys can be read-only"
    end
  end

  # Called after create to send the public key added email notification.
  def notify_creation
    if repository
      RepositoryMailer.deploy_key_added(self).deliver_later unless T.must(repository).is_importing?
    else
      AccountMailer.public_key_added(self).deliver_later if notify_user_key_action_via_email?
    end
  end

  public

  include Instrumentation::Model

  def event_payload
    event = {
      public_key_id: id,
      title: title,
      key: key,
      fingerprint: fingerprint,
      created_by: created_by,
      read_only: read_only?.to_s,
    }

    if repository_id? && repository&.owner&.organization?
      event[:org] = owner
    end

    if GitHub.context[:actor_id]
      event[:actor_id] = GitHub.context[:actor_id]
    end
    if GitHub.context[:actor]
      event[:actor] = GitHub.context[:actor]
    end

    if user_id?
      event[:user] = user
    elsif repository_id?
      event[:repo] = repository
    end

    event
  end

  # Public: Instrument creating new public keys.
  #
  # payload - event payload Hash.
  #           :actor - The User adding this public key.
  #                    Default: the user (most add their own).
  #
  # Returns nothing.
  def instrument_creation(payload = {})
    GitHub.dogstats.increment("public_key", tags: [
      "action:create",
      "key_bits:#{key_bit_length}",
      "key_type:#{parsed_key.algo}",
      "member_type:#{repository_key? ? 'repository' : 'user' }"])
    instrument :create, payload
  end

  # Public: Instrument public key updates.
  #
  # payload - event payload Hash.
  #           :actor - The User updating this public key.
  #                    Default: the user (most update their own).
  #
  # Returns nothing.
  def instrument_update(payload = {})
    instrument :update, payload
  end

  # Public: Instrument public key deletion.
  #
  # options - event payload Hash.
  #           :actor - The User deleting this public key.
  #           Default: the user (most remove their own).
  #
  # Returns nothing.
  def instrument_deletion(payload = {})
    instrument :delete, payload.merge(explanation: @destroy_explanation, incident: @incident_reference)
    GitHub.dogstats.increment("public_key", tags: ["action:destroy", "explanation:#{@destroy_explanation.to_s.gsub(/_/, "-")}"])
  end

  # Public: Destroy access and instrument the deletion using the provided
  # explanation
  #
  # explanation - The reason the record is being destroyed
  #
  # Returns the result of calling destroy() on the model instance.
  def destroy_with_explanation(explanation, incident_reference: nil)
    unless self.class.destroy_explanation(explanation)
      raise ArgumentError, "invalid destroy explanation: #{explanation}"
    end
    @destroy_explanation = explanation
    @incident_reference = incident_reference
    destroy
  end

  # Public: Generate webhook payload before destroy.
  #
  #
  # Returns nothing.
  def generate_webhook_payload
    return unless repository_id?

    event = Hook::Event::DeployKeyEvent.new(
      action: :deleted,
      key_id: self.id,
      actor_id: (GitHub.context[:actor_id] || User.ghost.id),
      repository_id: self.repository_id,
      triggered_at: Time.now,
    )

    @delivery_system = Hook::DeliverySystem.new(event)
    @delivery_system.generate_hookshot_payloads
  end

  # Public: Enqueue the pre-generated payload into the background job system
  #
  #
  # Returns nothing.
  def queue_webhook_delivery
    return unless repository_id?

    unless defined?(@delivery_system)
      raise "'generate_webhook_payload' must be called before 'queue_webhook_delivery'"
    end

    @delivery_system&.deliver_later
  end

  # Window of time between access logs writes.
  #
  # Returns a duration.

  ACCESS_THROTTLING = 1.week
  ACCESS_CUTOFF_DATE = Time.utc(2014, 3, 5)
  RECENTNESS = 1.week

  def last_accessed_after_cutoff?
    if created_at && T.must(created_at) > ACCESS_CUTOFF_DATE
      true
    else
      false
    end
  end

  def access_cutoff_date
    ACCESS_CUTOFF_DATE.strftime("%B %d, %Y")
  end

  def self.last_accessed_memcache_key(id)
    "public_keys:last_accessed:#{id}"
  end

  # Public: Has this key been accessed in the access throttling period.
  #
  # now - The time to use to determine the end of the throttling period.
  #
  # Returns true if accessed within period else false.
  def self.accessed_within_throttling_period?(accessed_at:)
    accessed_at && accessed_at > (Time.zone.now - ACCESS_THROTTLING)
  end

  # Public: Register this public key has been used
  #
  # This only updates periodically to prevent a lot of writes if used often in a
  # short period of time.
  #
  # Returns nothing
  def self.access(id:, last_accessed_at:)
    return if accessed_within_throttling_period?(accessed_at: last_accessed_at)

    now = Time.zone.now
    if GitHub.cache.add(last_accessed_memcache_key(id), now, ACCESS_THROTTLING.to_i)
      PublicKeyAccessJob.perform_later(id, now.to_i)
    end

    GitHub.instrument "public_key.access", public_key_id: id
  end

  def access
    self.class.access(id: id, last_accessed_at: accessed_at)
  end

  def access!(time)
    return if self.class.accessed_within_throttling_period?(accessed_at: accessed_at)

    ActiveRecord::Base.connected_to(role: :writing) do
      threshold = ACCESS_THROTTLING.ago.to_formatted_s(:db)
      self.class.connection.update(Arel.sql(<<-SQL, id: id, accessed_at: time, threshold: threshold))
        UPDATE public_keys SET accessed_at = :accessed_at
        WHERE id = :id AND (accessed_at < :threshold OR accessed_at IS NULL)
      SQL
    end

    T.must(oauth_authorization).bump(time) if oauth_authorization

    nil
  end

  def last_access_date
    last_access_time.to_date
  end

  def last_access_time
    accessed_at&.in_time_zone
  end

  def recent?
    accessed_at && T.must(accessed_at) > RECENTNESS.ago
  end

  def weak_key?
    return false unless parsed_key.algo == SSHData::PublicKey::ALGO_RSA
    GitHub::SSH.weak_rsa_key?(parsed_key.openssl)
  rescue SSHData::Error
    true
  end

  def target_for_conditional_access
    owner
  end

  private

  # Private: Deletes associated OauthAuthorization if the authorization has no
  # remaining authorized objects (public keys and accesses).
  #
  # Returns nothing.
  def destroy_oauth_authorization
    T.must(oauth_authorization).destroy_with_args(entry_point: :public_key_destroy_callback) if T.must(oauth_authorization).unused?
  end

  def verified_at_did_change?(record)
    record.previous_changes.key?(:verified_at) &&
      record.previous_changes[:verified_at].first != record.previous_changes[:verified_at].last
  end

  # Validate that the given public key is unique to the user across both the
  # `public_keys` table and the `git_signing_ssh_public_keys` table.
  def auth_key_is_not_someone_elses_signing_key
    return if !errors[:key].empty?

    cond = ["fingerprint_sha256 = ?", fingerprint_sha256]
    existing_key = GitSigningSshPublicKey.find_by(fingerprint_sha256: fingerprint_sha256)

    if existing_key && existing_key.user_id != user_id
      errors.add :key, "is already in use"
    end
  end
end
