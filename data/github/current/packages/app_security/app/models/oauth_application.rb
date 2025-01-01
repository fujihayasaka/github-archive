# typed: true
# frozen_string_literal: true

# An OauthApplication is a registered application or services that integrates
# with GitHub. OauthApplications can act on behalf of users that explicitly
# authorize them to do so.
class OauthApplication < ApplicationRecord::Domain::Integrations
  include PrimaryAvatar::Model
  include Avatar::List::Model
  include GitHub::Validations
  include GitHub::FlipperActor
  include GitHub::VexiActor
  include OauthAccess::Provider
  include OauthAccess::ClientId
  include Marketplace::Listable
  include Proxima::Syncable
  include AppNameValidity
  include GitHub::RateLimitedCreation
  include Rest::HasPinnedApiVersion
  include Coders::CodableColumn
  include Spam::Spammable
  include OauthApplication::FeatureFlagMethods
  include AppEmuOwnership

  IDENTICON_TYPE = "oauth_app".freeze

  DEFAULT = {
    name: "Personal Access Token",
    url: GitHub.developer_help_url + "/v3/oauth_authorizations/",
    callback_url: "https://github.com",
  }.freeze

  def self.client_id_types
    {
      /\AOv2([0-9a-z]{17})\z/i => :v2,
      /\A([0-9a-f]{20})\z/i => :v1,
    }
  end

  def self.client_id_prefix(type:)
    case type
    when :v1
      ""
    when :v2
      "Ov2"
    end
  end

  def self.client_id_seperator(type:)
    case type
    when :v1
      ""
    when :v2
      opaque_generated_location_specifier
    end
  end

  def self.client_id_random_part_length(type:)
    type == :v1 ? 10 : 14
  end

  before_validation :generate_client_id_if_needed
  validates_presence_of :key
  validates_uniqueness_of :key, case_sensitive: false

  # default error message for an invalid URL
  INVALID_URL_MESSAGE = "must be a valid URL".freeze

  # Public: A special oauth application id that we use to generate personal
  # tokens for scripts and such (id = 0).
  PERSONAL_TOKENS_APPLICATION_ID   = 0.freeze
  PERSONAL_TOKENS_APPLICATION_TYPE = "OauthApplication".freeze
  PERSONAL_TOKENS_CLIENT_ID        = ("0" * 20).freeze

  def self.default(note = nil, url = nil)
    if note.present? || url.present?
      options = {}
      options[:name] = note if note.present?
      options[:url] = url if url.present?
      pseudo(options)
    else
      @default ||= pseudo
    end
  end

  def self.pseudo(options = {})
    oauth_app = new(DEFAULT.merge(options))
    oauth_app.id  = PERSONAL_TOKENS_APPLICATION_ID
    oauth_app.key = PERSONAL_TOKENS_CLIENT_ID

    oauth_app
  end

  # Public: The User record that owns (created) this oauth application.
  belongs_to :user
  validates_presence_of :user_id
  setup_spammable :user

  # Public: OauthAccesses granted to this application.
  has_many :accesses,
    class_name: "OauthAccess",
    as: :application,
    dependent: :destroy

  # Public: OauthAccesses granted to this application.
  has_many :authorizations,
    class_name: "OauthAuthorization",
    as: :application,
    dependent: :destroy

  # Internal: PublicKeys created by this application.
  has_many   :public_keys, through: :accesses

  # Public: Hooks created on behalf of a user by this application.
  has_many   :hooks, dependent: :destroy

  # Public: Client secrets for application.
  has_many :client_secrets,
    -> { order(id: :desc) },
    class_name: "OauthApplicationClientSecret",
    inverse_of: :oauth_application,
    dependent: :delete_all

  accepts_nested_attributes_for :client_secrets,
    reject_if: :all_blank,
    allow_destroy: true

  # Public: Logo associated with this oauth application (optional, defaults to owner's avatar).
  belongs_to :logo, class_name: "OauthApplicationLogo", foreign_key: :logo_id, dependent: :destroy # rubocop:todo Rails/InverseOf

  # Public: Association relationship for OauthApplicationApprovals.
  has_many :approvals, # rubocop:todo Rails/InverseOf
    class_name: "OauthApplicationApproval",
    foreign_key: :application_id,
    dependent: :delete_all

  # Public: Association relationship for OauthApplicationTransfers.
  has_one :transfer, # rubocop:todo Rails/InverseOf
    class_name: "OauthApplicationTransfer",
    foreign_key: :application_id,
    dependent: :destroy

  # Public: The listing information for the Integration Directory, if any.
  has_one :integration_listing,
    as: :integration,
    dependent: :destroy

  has_many :application_callback_urls,
    as: :application,
    inverse_of: :application
  destroy_dependents_in_background :application_callback_urls

  accepts_nested_attributes_for :application_callback_urls, reject_if: :all_blank, allow_destroy: true

  # Public: String URL of this oauth application.
  # column :url
  validates_presence_of :url
  validate :check_application_url

  # Public: String callback URL of this oauth application.
  # column :callback_url
  validates_presence_of :callback_url
  validate :check_callback_url
  validates :callback_url, unicode3: true

  validates_associated :application_callback_urls

  # Public: String name of this oauth application.
  # column :name
  validates :name, presence: true, length: { maximum: 255 }
  validate :restrict_names_with_github
  validate :restrict_name_unicode_chars
  validate :restrict_names_with_urls
  before_validation :remove_extra_spaces_from_name

  # Public: String description of this oauth application.
  # column :description
  validates :description, unicode3: true

  # Public: String client_id of this oauth application.
  # column :key
  validates_presence_of :key
  validates_uniqueness_of :key, case_sensitive: false

  # Public: Integer customer API rate limit for this application.
  # column :rate_limit

  # Public: Boolean flag to specify application is fully trusted. Full trust
  # applications are owned and operated by GitHub, Inc. and allow OauthAccess
  # granting WITHOUT user approval.
  # column :full_trust
  # TODO: Delete this comment when full_trust column is dropped:
  # https://github.com/github/ecosystem-apps/issues/643

  # Public: String host of this application's URL (set automatically).
  # column :domain
  validate :set_domain
  validates :domain, length: { maximum: 100 }, unicode3: true, allow_blank: true

  validates_with CreatedApplicationsLimitValidator, on: :create

  # Public: Integer state of the oauth application.
  # column :state
  #   :active           - Active and allowed to have oauth accesses (default).
  #   :suspended        - Suspended from generating oauth accesses due to abuse
  #                       or security concerns.
  #   :pending_deletion - In the process of being deleted in a background job.
  #                       This state is largely for the UI.
  enum :state, { active: 0, suspended: 1, pending_deletion: 2 }


  # Public: Array of String scopes this application can request (full trust
  # applications only right now).
  # array :scopes

  serialize_with_coder :raw_data, Coders::OauthApplicationCoder

  # Public: Set the required scopes for this application (full trust
  # applications only right now).
  # scopes - Strong comma separated list of scopes (or Array of String scopes).
  #
  # Returns nothing.
  def set_scopes(scopes)
    self.scopes = OauthAccessTokens::Domain.normalize_scopes(scopes, visibility: :all)
  end

  before_validation :normalize_bgcolor

  after_create_commit  :instrument_creation

  after_update_commit  :instrument_suspension,   if: [:state_previously_changed?, :suspended?]
  after_update_commit  :instrument_unsuspension, if: [:state_previously_changed?, :active?]

  # NOTE: Moving instrument_deletion to a commit callback causes test failures in
  # many tests related to missing User models due to the user deletion flow.
  after_destroy :instrument_deletion # rubocop:disable GitHub/AfterCommitCallbackInstrumentation

  # Returns OauthApplications that the given User owns or can manage because they're owned by an
  # Organization for which the given User is an admin.
  scope :adminable_by, ->(user) {
    user_ids = [user.id]

    adminable_org_ids = Ability.user_admin_on_organizations(
      actor_id: user.id,
    ).pluck(:subject_id)
    user_ids = user_ids.concat(adminable_org_ids) if adminable_org_ids.present?

    where(user_id: user_ids)
  }

  # Returns OauthApplications that do not have a Marketplace::Listing.
  scope :not_in_marketplace, -> {
    left_outer_joins(:marketplace_listing).where(marketplace_listings: { listable_id: nil })
  }

  scope :blockable_client_apps, -> {
    where(id: Apps::Privileged.all_ids_with_capability(:blockable_first_party_client, type: "OauthApplication"))
  }

  attr_writer :skip_restrict_names_with_github_validation

  def target_for_conditional_access
    owner.target_for_conditional_access
  end

  def async_target_for_conditional_access
    async_owner.then(&:async_target_for_conditional_access)
  end

  # OauthApplications default to the global default rate limit, but an
  # application can be granted a higher rate limit to get more calls. Use
  # #set_temporary_rate_limit to set a 3-day rate limit increase for initial
  # imports and that kind of thing.
  #
  # Returns the rate limit integer value for calls per hour
  def rate_limit
    temporary_rate_limit || self[:rate_limit] || GitHub.api_default_rate_limit
  end

  def temporary_rate_limit
    if temporary_rate_limit_expires_at&.future?
      self[:temporary_rate_limit]
    end
  end

  def set_temporary_rate_limit(limit, duration = 3.days)
    update! temporary_rate_limit: limit, temporary_rate_limit_expires_at: duration.from_now
  end

  def using_temporary_rate_limit?
    !temporary_rate_limit.nil?
  end

  # Public: check if a url is a direct match of a url in the
  # application_callback_urls. Then also makes sure it's a valid
  # callback url?
  #
  # Returns true if the url matches and is a valid or false
  # otherwise.
  def callback_url_direct_match?(url)
    if application_callback_urls.exists?(url: url)
      GitHub.dogstats.increment "oauth_application", tags: ["action:callback_url_exact_match"]
      return valid_callback_url?(url)
    elsif Apps::Privileged.capable?(:proxima_first_party_sync, app: self)
      if FeatureFlag.vexi.enabled?(:oauth_redirect_exact_match_fix, self, default: false)
        if application_callback_urls.any? { |application_callback_url| application_callback_url.url == url }
          GitHub.dogstats.increment "oauth_application", tags: ["action:callback_url_exact_match"]
          return valid_callback_url?(url)
        end
      else
        if application_callback_urls.any? { |application_callback_url| application_callback_url.url.match?(url) }
          GitHub.dogstats.increment "oauth_application", tags: ["action:callback_url_exact_match"]
          return valid_callback_url?(url)
        end
      end
    end

    false
  end

  # OauthApplications can belong to user or organizations. Use this method to
  # be a little more clear.
  #
  # Returns the User or Organization owner of the application
  def owner
    user
  end

  def async_owner
    Platform::Loaders::ActiveRecord.load(::User, user_id)
  end

  # Public: A version of the app's owner that is suitable for use in views and
  # API responses. Accounts for things like multi-tenancy, synchronization and
  # first/third-party behavior.
  #
  # Returns a AppDisplayOwner.
  def display_owner
    AppDisplayOwner.new(app: self, actual_owner: owner)
  end

  # Public: Set the callback URL for this oauth application
  def callback_url=(url)
    set_application_callback_urls(url)
  end

  # Public: Returns the first callback URL from application_callback_urls if any exist,
  # otherwise it will return the callback_url attribute or fall back to
  # assigning callback_url to url.
  def callback_url
    if raw_callback_url
      if ::ProximaAppRequest::TenantScopedUrl.should_generate?(url: raw_callback_url, app: self)
        ::ProximaAppRequest::TenantScopedUrl.generate(raw_callback_url, self)
      else
        raw_callback_url
      end
    else
      self.callback_url = url
    end
  end

  # Public: the value of callback_url stored in the database
  def raw_callback_url
    if application_callback_urls.any?
      application_callback_urls.first&.raw_url
    else
      read_attribute(:callback_url)
    end
  end

  # Public: Set the list of application callback URLs to be validated against
  # redirect_uri during the access token request. Ensures the legacy
  # `callback_url` attribute stays up-to-date by always setting it based on the
  # first supplied URL argument.
  #
  # TODO: When multiple callback URLs/redirect URIs have been shipped this
  # method should be removed. Tracking issue:
  # https://github.com/github/ecosystem-apps/issues/7409
  #
  # Destroys and recreates the associated ApplicationCallbackUrl records if the
  # OauthApplication is persisted.
  #
  # urls -  A splat of String URLs, or an Array of Hashes containing
  #         ApplicationCallbackUrl model attributes.
  #
  # Returns nothing.
  def set_application_callback_urls(*urls)
    if self.persisted? && application_callback_urls.exists?
      application_callback_urls.destroy_all
    end
    association(:application_callback_urls).reset

    @callback_uri = nil
    urls = Array(urls).flatten
    filtered_urls = urls.reject { |u, _| u.blank? }.uniq

    if filtered_urls.length == 0 && url # Fall back to legacy `url` attribute when other URLs have been filtered out.
      self.application_callback_urls_attributes = [{ url: url }]
    else
      if filtered_urls.all? { |u| u.is_a?(Hash) } # Directly assign ApplicationCallbackUrl attribute hashes.
        self.application_callback_urls_attributes = filtered_urls
      else                                        # Handle legacy `callback_urls` attributes.
        self.application_callback_urls_attributes = filtered_urls.map do |callback_url|
          { url: callback_url }
        end
      end
    end

    write_attribute :callback_url, application_callback_urls.first&.raw_url
  end

  def callback_uri
    return if callback_url.blank?
    @callback_uri ||= Addressable::URI.parse(callback_url)
  end

  # Public: Boolean flag to tell if an application uses Oauth scopes.
  #
  # Returns true for all OauthApplications.
  def uses_scopes?
    true
  end

  # Public: Boolean flag to tell if an application is an OAuth app
  # owned by GitHub.
  #
  # Returns true if this application is owned by GitHub, Inc.
  def github_owned?
    user_id == GitHub.trusted_apps_owner_id
  end

  # Indicates if this application can be blocked.
  #
  # Returns a Boolean representing whether the app has been granted the correct
  # internal apps capability.
  def blockable_client_app?
    Apps::Privileged.capable?(:blockable_first_party_client, app: self)
  end

  # Indicates if the application should be exempted from organization
  # OAuth Application policies for 3rd party apps
  #
  # Returns a Boolean.
  def third_party_oap_exempt?
    Apps::Privileged.capable?(:organization_oauth_app_policy_exempt, app: self)
  end

  # Indicates if the application should be exempted from organization
  # OAuth Application policies for 1st and 3rd party apps
  #
  # Returns a Boolean.
  def oap_exempt?
    third_party_oap_exempt? && !blockable_client_app?
  end

  # Indicates if third party restrictions can be applied to this application.
  # True for all OAuth Applications.
  def third_party_restrictions_applicable?
    true
  end

  # Public: Boolean flag to indicate if the app is owned by a given
  # user or organization.
  #
  # user_or_org - User or Organization instance.
  #
  # Returns a Boolean.
  def owned_by?(user_or_org)
    return false unless user_or_org.is_a?(User)

    self.user_id == user_or_org.id
  end

  def manageable_by?(user)
    owner.adminable_by?(user)
  end

  def user_token_expiration_enabled?
    false
  end

  def validate_client_secret(plaintext)
    return false if plaintext.blank?

    hash = OauthApplicationClientSecret.hash_for(plaintext)

    if client_secret = client_secrets.find_by(secret_hash: hash)
      client_secret.access
      true
    end
  end

  def update_secret_accessed_at(plaintext)
    hash = OauthApplicationClientSecret.hash_for(plaintext)
    client_secret = client_secrets.where(secret_hash: hash).first!
    OauthApplicationClientSecret.access(id: client_secret.id, last_accessed_at: client_secret.accessed_at)
  end

  def generate_client_secret(creator:)
    secret = self.client_secrets.transaction do
      self.client_secrets.create(creator: creator)
    end
    instrument :generate_client_secret
    secret
  end

  def max_client_secrets_reached?
    client_secrets.count >= OauthApplicationClientSecret::MAX_SECRETS
  end

  def async_revoke_tokens(entry_point:)
    # TODO: Pass entry point to job once method signature change has shipped.
    RemoveOauthAppTokensJob.perform_later(id)
  end

  # Return a human readable string for use in audit logs.
  def to_s
    "#{self.class.name}:#{self.key}"
  end

  # Public: Transfers the application to a target organization and deletes
  # any transfer requests for the application.
  #
  # target - The Organization to transfer the app to.
  # requester  - The User requesting the transfer.
  # responder  - The User completing the transfer.
  #
  # Returns a Boolean.
  def transfer_ownership_to(target, requester:, responder:)
    return false unless valid_target?(target)

    instrument :transfer, \
      transfer_from: user,
      transfer_to: target,
      requester: requester,
      responder: responder

    self.user = target

    transaction do

      save!
      T.must(transfer).destroy if transfer.present?

      approvals.where(organization_id: target.id).destroy_all

      true
    end
  end

  def set_domain
    if url.nil? || !T.must(url).valid_encoding?
      self.domain = nil
    else
      self.domain = Addressable::URI.parse(url.to_s).try(:host)
      if domain.present? && T.must(domain).length > 100
        errors.add(:url, "has a domain that is too long (maximum is 100 characters)")
      end
    end
  rescue Addressable::URI::InvalidURIError
  end

  # Public: The number of public keys created by this application.
  #
  # Returns a Integer.
  def public_key_count
    public_keys.count
  end

  # Public: Can this App be deleted? Prevents the App being
  # deleted in cases where assocated marketplace listing has subs.
  #
  # - Apps with marketplace listing subs can't be deleted
  #
  def can_delete?
    if FeatureFlag.vexi.enabled?(:marketplace_allow_deleting_apps_with_no_active_subscriptions, default: false)
      return false if marketplace_listing&.subscription_items&.active.present?
    else
      return false if marketplace_listing&.subscription_items.present?
    end
    true
  end

  # Public: Queues a job to destroy the application.
  #
  # For applications with a large number of OauthAccesses and/or a large number
  # of PublicKeys, destroying the app might take a while. Web/API requests
  # should use this method instead of using #destroy directly.
  #
  # Returns nothing.
  def async_destroy
    self.state = :pending_deletion
    save

    OauthApplicationDeleteJob.perform_later(T.must(id))
  end

  include Instrumentation::Model

  def event_context(prefix: event_prefix)
    {
      "#{prefix}".to_sym    => name,
      "#{prefix}_id".to_sym => id,
    }
  end

  # Public: Determine whether the given user is authorized to administer this
  # application.
  #
  # user - A User instance.
  #
  # Returns a Boolean.
  def adminable_by?(user)
    owner.adminable_by?(user)
  end

  def pending_transfer?
    transfer.present?
  end

  # Public: Register GitHub trusted applications.
  # If the application already exists, its attributes are updated.
  # This is mostly used in enterprise configuration processes to register Gist, Hookshot and the native apps in the installation.
  #
  # name - is the application name.
  # client_id - is the client id token.
  # client_secret - is the client secret.
  # url - is the application url. GitHub.url + name by default.
  # callback - is the callback url. GitHub.url + name by default.
  #
  # Returns the new oauth application.
  def self.register_trusted_application(name, client_id, client_secret, url, callback = nil)
    if client_secret
      hashed_secret = OauthApplicationClientSecret.hash_for(client_secret)
      last_eight = client_secret.last(8)
    end

    register_hashed_trusted_application(name,
                                        client_id,
                                        hashed_secret,
                                        last_eight,
                                        url,
                                        callback)
  end

  # Public: Register GitHub trusted applications with hashed secrets.
  # If the application already exists.
  # This is used in enterprise configuration to register Apps with hashed secrets. E.g. GitHub Desktop, GitHub iOS etc.
  #
  # name - The application name.
  # client_id - The client ID token.
  # hashed_secret - hashed client secret.
  # secret_last_eight - last 8 charecters of original secret.
  # url - is the application url. GitHub.url + name by default.
  # callback - is the callback url. GitHub.url + name by default.
  #
  # Returns the new oauth application.
  def self.register_hashed_trusted_application(name, client_id, hashed_secret, secret_last_eight, url, callback = nil)
    owner_id = GitHub.trusted_apps_owner_id
    host  = Addressable::URI.parse(GitHub.url)

    url          = host.join(url)
    callback_url = host.join(callback || url)

    oauth_app = OauthApplication.where(user_id: owner_id, name: name).first || OauthApplication.new

    oauth_app.name                   = name
    oauth_app.user                   = Organization.find_by(id: owner_id)
    oauth_app.key                    = client_id
    oauth_app.url                    = url.to_s
    oauth_app.callback_url           = callback_url.to_s
    unless oauth_app.new_record?
      existing_secret = oauth_app.client_secrets.where(secret_hash: hashed_secret, secret_last_eight: secret_last_eight).any?
    end

    unless existing_secret
      if oauth_app.max_client_secrets_reached?
        oauth_app.client_secrets = oauth_app.client_secrets[..-2]
      end
      oauth_app.client_secrets.build(creator: User.ghost,
                                       secret_hash: hashed_secret,
                                       secret_last_eight: secret_last_eight)
    end

    unless oauth_app.save
      fail "Failed to save #{name} Oauth Application settings"
    end

    oauth_app
  end

  # Public: Safely query for an OauthApplication by key
  #
  # Returns an OauthApplication or nil
  def self.find_by_key(key)  # rubocop:disable GitHub/FindByDef
    # Enforce key(s) is/are strings matching the correct key pattern
    string_key = Array(key).map(&:to_s).select { |k| OauthAccessTokens::Domain.client_id?(k, application_klass: OauthApplication) }

    where(key: string_key).first
  end

  # Public: Safely query for an OauthApplication by key
  #
  # Returns an OauthApplication or raises ActiveRecord::RecordNotFound
  # if an OauthApplication is not found
  def self.find_by_key!(key)  # rubocop:disable GitHub/FindByDef
    find_by_key(key) || (raise ActiveRecord::RecordNotFound)
  end

  # Public: Determines the number of OauthApplications created by user
  #
  # Returns an Integer
  def self.created_by_count(user)
    user.oauth_applications.count
  end

  # Public: Get an image URL for the logo that best represents this app, ignoring the current
  # user and whether this app is listed in the Marketplace or not.
  def preferred_avatar_url(size: 80)
    async_preferred_avatar_url(size: size).sync
  end

  def async_preferred_avatar_url(size: 80)
    return @async_preferred_avatar_url[size] if defined?(@async_preferred_avatar_url)

    @async_preferred_avatar_url = Hash.new do |hash, key|
      hash[key] = async_primary_avatar.then do |primary_avatar|
        canonical_avatar_url = ProximaAppSynchronization.canonical_avatar_url_for(self)
        next canonical_avatar_url if canonical_avatar_url

        next primary_avatar_url(key) if primary_avatar

        async_logo.then do |logo|
          next logo.storage_external_url if logo

          UrlHelpers.app_identicon_path(IDENTICON_TYPE, id)
        end
      end
    end

    @async_preferred_avatar_url[size]
  end

  def primary_avatar_path
    @primary_avatar_path ||= "/oa/#{id}"
  end

  def tenant_slug_for_avatar
    user&.tenant_slug_for_avatar
  end

  def avatar_editable_by?(user)
    adminable_by?(user)
  end

  def destroy_logo
    return if logo_id.nil?
    logo&.destroy
    update(logo_id: nil)
  end

  def keep_old_avatar?
    false
  end

  def handle_previous_avatar(primary)
    super
    destroy_logo
  end

  # Public: Returns an elasticsearch query string that will find all of this
  # applications's audit log events
  #
  # Returns a String which can be passed to elasticsearch as a `query_string`
  def audit_log_query
    # Some audit log entries use application_id and some use oauth_application_id,
    # so we need to search for both with an OR query.
    # See https://github.com/github/github/issues/58540
    "(data.oauth_application_id:#{id} OR data.application_id:#{id})"
  end

  def audit_log_kql_query
    "webevents | where data.oauth_application_id == '#{id}' or data.application_id == '#{id}'"
  end

  # Public: Indicates if the application should use strict URL validation for
  # registered callback URLs.

  # Note: Prior to adding support for registering multiple callback URLs, we
  # did less strict URL validation, as some applications relied on adding
  # things such as subpaths and subdomains to their callback URL. However, for
  # any application that opts in to multiple callback URLs we will start
  # enforcing strict validation, as our less strict validation has been a
  # source of security issues.
  #
  # Returns a Boolean
  def strict_callback_url_validation?
    application_callback_urls.size > 1
  end

  # Public: Indicates if the application is owned by GitHub.
  #
  # Returns a Boolean.
  def owned_or_operated_by_github?
    return true if owner&.id == GitHub.trusted_apps_owner_id
    Apps::Privileged.capable?(:operated_by_github, app: self)
  end

  def synchronization_fingerprint
    canonical = [
      updated_at,
      application_callback_urls.map(&:updated_at).sort.join,
      owner.display_login, # Similar to user_id but include login changes
      owner.primary_avatar_path # Avatar changes
    ].join

    Digest::SHA256.hexdigest(canonical)
  end

  private

  def normalize_bgcolor
    return if bgcolor.blank?

    self.bgcolor = bgcolor.sub(/\A#/, "")
  end

  def restrict_name_unicode_chars
    if name.present? && !GitHub::UTF8.valid_unicode3?(name)
      errors.add(:name, "should not contain non unicode characters")
    end
  end

  def restrict_names_with_github
    return unless name && user
    # All automated creation of OAuth apps happens via methods that either
    # insert directly into the database (a la enterprise-2/ghe-run-migrations
    # script) or the `.register_hashed_trusted_application`, which always sets
    # the `owner_id` to be the trusted apps owner and passes this test.
    return if github_owned?
    return if T.must(user).employee? && T.must(user).site_admin?
    return if @skip_restrict_names_with_github_validation

    if name_starts_with_github?
      errors.add(:name, "should not begin with 'GitHub' or 'Gist'")
    end

    if name_implies_github_affiliation?
      errors.add(:name, "should not imply the application is from GitHub")
    end
  end

  def restrict_names_with_urls
    if name.present? && name_includes_urls?
      errors.add(:name, "should not include any URLs")
    end
  end

  # Private: Default attributes for auditing
  def event_payload
    payload = {
      oauth_application: self,
      state: self.class.states[state.to_s],
      rate_limit: rate_limit,
      application_url: url,
      callback_url: callback_url,
    }

    if T.must(user).user?
      payload[:user] = user
    else
      payload[:org] = user
    end

    payload
  end

  # Private: Instrument OAuth application creation.
  #
  # Returns nothing.
  def instrument_creation
    instrument :create
  end

  # Private: Instrument OAuth application deletion.
  #
  # Returns nothing.
  def instrument_deletion
    instrument :destroy
  end

  def instrument_suspension
    instrument :suspend
  end

  def instrument_unsuspension
    instrument :unsuspend
  end

  # Private: validate application callback_url is a String and valid URL.
  def check_callback_url
    unless callback_url.is_a?(String)
      return errors.add(:"callback_url", INVALID_URL_MESSAGE)
    end

    unless valid_callback_url?(callback_url)
      errors.add(:"callback_url", INVALID_URL_MESSAGE)
    end
  end

  # Private: validate application url is a String and valid URL.
  def check_application_url
    unless url.is_a?(String)
      return errors.add(:"url", INVALID_URL_MESSAGE)
    end

    unless IntegrationUrl.valid_application_url?(url)
      errors.add(:"url", INVALID_URL_MESSAGE)
    end
  end

  def valid_callback_url?(url)
    # When multiple callback URLs are registered we perform more strict validation.
    options = {}
    if strict_callback_url_validation?
      options[:blocked_query_keys] = OauthUtil::RESERVED_REDIRECT_URI_QUERY_KEYS
      options[:allow_fragment] = false
    end
    IntegrationUrl.valid_callback_url?(url, options)
  end
end
