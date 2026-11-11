# typed: true
# frozen_string_literal: true

require "oauth_util"

# An OauthAccess represents a user giving an OauthApplication access to make
# requests on their behalf. OauthAccesses are scoped to allow granular access
# to resources.
class OauthAccess < ApplicationRecord::Domain::Integrations
  include GH::Associations::BatchMethodAdapters
  include OauthAccessTokens::IOauthAccess
  include GitHub::Validations
  include TokenExpirable
  include Coders::CodableColumn
  include ProgrammaticAccess::ExpirationLimit
  include GitHub::VexiActor
  include GitHub::Memoizer

  OAUTH_PREFIX = "gho_"
  PAT_PREFIX = "ghp_"
  USER_TO_SERVER_PREFIX = "ghu_"

  VALID_INSTALLATION_TYPES = %w(ScopedIntegrationInstallation SiteScopedIntegrationInstallation)
  attr_accessor :integration_version_number, :entry_point

  alias_attribute :issued_at, :last_issued_at

  extend GitHub::UtcTimestamp::ClassMethods
  utc_timestamp :expires_at

  # Code/Token entropy stuff
  CODE_BYTES  = 10
  TOKEN_BYTES = 30

  # Require code to be a 20 hex character string
  CODE_PATTERN = /\A[a-f0-9]{20}\z/

  TOKEN_LENGTH = 36
  TOKEN_PREFIX_LENGTH = 4
  TOKEN_CHECKSUM_LENGTH = 6

  # Require token_last_eight to be a 8 hex character string
  TOKEN_LAST_EIGHT_PATTERN = /\A[a-zA-Z0-9]{8}\z/

  # Require hashed_token to be a 44 character base64 string (base64 of 32 byte hash)
  HASHED_TOKEN_PATTERN = /\A[A-Za-z0-9+\/=]{44}\z/

  # Use SHA256 for hashing tokens
  HASHED_TOKEN_DIGEST = Digest::SHA256

  DEFAULT_INSTALLATION_TOKEN_EXPIRY = 8.hours

  COPILOT_CODING_AGENT_APPLICATION_ID = 1143301

  # We return a fresh token on every OAuth dance. Since we do not enforce an
  # expiration using OAuth refresh tokens, we need another way to limit
  # unbounded growth of OAuthAccess records over time. We will do this by
  # restricting the number of accesses that can be created for a (user,
  # application, and scope) tuple. By using this tuple we minimize the
  # possibility of scenarios such as the following:
  #  * User performs one OAuth dance with repo scope.
  #  * User performs many more OAuth dances with the default empty scope.
  #  * The repo scope token gets destroyed because it is the oldest.
  MAXIMUM_ACCESSES_FOR_APP = 10

  # A small number of applications have been affected by our newly introduced
  # limits on OAuth accesses (MAXIMUM_ACCESSES_FOR_APP). Since this change was
  # not announced in advance, we are allowing a temporary override for a handful
  # of applications that were designed in a way that relied on, effectively, an
  # infinite number of accesses for a user. The intent is for these developers
  # to update their design to support our new limits. This is a reasonable
  # expectation in so far as most OAuth providers have similar limits on the
  # number of accesses an application can create. This is not meant as a
  # long-term solution for these applications. As a result, the expectation is
  # that an override should only be used for 1-2 months. The below hash maps an
  # `application_id` to the temporary limit. If at all possible, try to keep the
  # limit below 100. Alowing more than 100 accesses may require a transition to
  # destroy excess tokens after the temporary limit is removed.
  MAXIMUM_ACCESSES_FOR_APP_OVERRIDES = {
    # AWS CodePipeline - Added 7/28/2016
    189159 => 100,
    # AWS CodeDeploy - Added 7/28/2016
    140455 => 100,
    # Okta - Added 2/28/2018, updated 9/3/2024
    475360 => 450,
    # Azure AD SCIM Provisioning - Added 3/27/2020, updated 9/3/2024
    524102 => 450,
    # Copilot Coding Agent - Added 5/15/2025
    COPILOT_CODING_AGENT_APPLICATION_ID => 25
  }.freeze

  MAXIMUM_ACCESSES_FOR_EXPIRING_APP = 50

  # Time buffer to protect newly created tokens from immediate deletion.
  # Tokens created within this window are generally excluded from cleanup.
  NEW_TOKEN_DELETION_BUFFER = 1.minute

  TOKENS_EXCLUDED_FROM_INTEGRATION_TOKEN = %w[site_admin]

  SITE_ADMIN_SCOPES = %w[site_admin devtools biztools].to_set

  TOKEN_BATCH_SIZE = 100

  # NOTE: Scope are defined in app/api/access_control.rb

  extend GitHub::Encoding
  force_utf8_encoding :hashed_token

  def self.normalize_scopes(scopes, options = nil)
    Api::AccessControl.normalize_scopes(scopes, options)
  end

  def self.valid_scopes(scopes)
    Array(scopes).select { |sc| Api::AccessControl.acceptable_scopes[sc.to_s] }
  end

  def self.invalid_scopes(scopes)
    Array(scopes).reject { |sc| Api::AccessControl.acceptable_scopes[sc.to_s] }
  end

  # Internal: Returns Hash of valid hidden OAuth scopes.
  #
  # user - Optional User object.
  #
  # Hash object will include all hidden scopes as String keys and a Boolean
  # value if the user is eligible to enable the scope.
  def self.valid_hidden_scopes(user)
    {
      "site_admin" => !!user&.site_admin?,
      "devtools" => !!user&.devtools_scope?,
      "biztools" => !!user&.biztools_scope?,
    }
  end

  # Filter an array of scopes to only those that are public
  # on the OAuth authorization form.
  #
  # Returns an Array of String scopes
  def self.filter_public_scopes(scopes = nil)
    Array(scopes).
      select { |sc| Api::AccessControl.public_scopes[sc.to_s] }.
      compact.
      uniq.
      sort
  end

  # Internal - intended only for the SecretScanningAPI: Find OauthAccess records for the given tokens.
  #
  # tokens - An array of String tokens.
  #
  # Returns a Hash with tokens as the keys and OauthAccess records as values
  def self.for_tokens(tokens)
    hashed_tokens = tokens.each_with_object({}) do |token, hash|
      hash[token] = hash_token(token)
    end

    accesses = T.let({}, T::Hash[T.untyped, T.untyped])

    hashed_tokens.values.each_slice(TOKEN_BATCH_SIZE) do |slice|
      batches = where(hashed_token: slice)
        .includes(:user)
        .in_batches(of: TOKEN_BATCH_SIZE)

      slice_accesses = T.must(batches).each_record.index_by(&:hashed_token)
      accesses = accesses.merge(slice_accesses)
    end

    tokens.each_with_object({}) do |token, hash|
      hash[token] = accesses[hashed_tokens[token]]
    end
  end

  # Public: Lookup up an OauthAccess by token, ensuring it is not expired
  #
  # hashed: whether the token being passed is already hashed.
  #
  # Returns OauthAccess for active tokens or nil  otherwise
  def self.with_active_token(token, hashed: false)
    return if !token.is_a?(String) || token.blank?

    token = hash_token(token) unless hashed
    access = find_by(hashed_token: token)

    return unless access

    return access unless access.expired?

    nil
  end

  def self.checksum(token)
    crc_value = Zlib.crc32(token)
    Base62.encode(crc_value, min_length: 6)
  end

  # Public: Validates a raw token against its checksum.
  #
  # raw_token - The raw token to validate.
  #
  # Returns true if the checksum is valid, false otherwise.
  def self.validate_token_checksum(raw_token)
    return false if raw_token.blank?

    # Extract the token body and checksum
    token_body = raw_token[TOKEN_PREFIX_LENGTH...-TOKEN_CHECKSUM_LENGTH] # Token without the prefix and checksum
    token_checksum = raw_token[-TOKEN_CHECKSUM_LENGTH..] # Last 6 characters as checksum

    # Validate the checksum
    expected_checksum = self.checksum(token_body)
    token_checksum == expected_checksum
  end

  # Public: The User record that granted this access.
  # TODO: for domain iso cleanup, break the user association and convert belongs_to_domain into a normal prelude batch_method
  belongs_to :user # rubocop:disable GitHub/UseBelongsToDomain
  destroy_in_background_with :user
  belongs_to_domain(:user, foreign_key: :user_id, ar_relation: true, return_type: T.nilable(Users::IUser)) do |user_ids|
    ActiveRecord::Base.connected_to(role: :reading) { Users.domain.by_ids(user_ids) }
  end

  validates_presence_of :user_id
  validate :owner_is_human, on: :create
  validate :owner_meets_email_verification_requirements, on: :create

  # Public: The OauthApplication or Integration that has been granted access.
  belongs_to :application, polymorphic: true
  # Additional relationships specified with conditions, for internal use,
  # rather than needing to provide these details in explicit JOIN statements,
  # to allow calling methods on these as preloaded polymorphic associations.
  belongs_to :oauth_application, foreign_key: "application_id" # rubocop:todo Rails/InverseOf
  belongs_to :integration, foreign_key: "application_id" # rubocop:todo Rails/InverseOf

  validates_presence_of :application_id
  validates_presence_of :application_type

  # Public: The OauthApplication that has been granted access.
  belongs_to :authorization, class_name: "OauthAuthorization"

  # Public: PublicKeys created by this access.
  has_many :public_keys

  # Public: authorizations this credential has for an Enterprise.
  has_many :enterprise_credential_authorizations,
    class_name: "Business::CredentialAuthorization",
    as: :credential
  destroy_dependents_in_background :enterprise_credential_authorizations

  # Public: authorizations this credential has for an Organization.
  has_many :credential_authorizations,
    class_name: "Organization::CredentialAuthorization",
    as: :credential
  destroy_dependents_in_background :credential_authorizations

  # All of these records live outside mysql1 and should not be destroyed in the access transaction.
  belongs_to :installation, polymorphic: true
  after_commit :destroy_installation, on: :destroy

  has_one :refresh_token, as: :refreshable
  destroy_dependents_in_background :refresh_token

  has_one :device_authorization_grant
  destroy_dependents_in_background :device_authorization_grant

  # TODO: Code expiration in 10 minutes (max recommended).
  # Public: String temporary code to be exchanged for a token.
  # column :code
  validates_uniqueness_of :code, scope: :application_id, allow_nil: true, case_sensitive: false
  validates_format_of :code, with: CODE_PATTERN, allow_nil: true

  # Public: String code challenge for PKCE. Will always be 43 characters in length because we only allow SHA256 challenges
  # column :code_challenge
  validates :code_challenge, length: { is: 43 }, allow_nil: true

  # Public: String last eight characters of token.
  # column :token_last_eight
  validates_format_of :token_last_eight, with: TOKEN_LAST_EIGHT_PATTERN, allow_nil: true

  # Public: String base64 encoded SHA256 hash of token.
  # column :hashed_token
  validates_uniqueness_of :hashed_token, allow_nil: true, case_sensitive: true
  validates_format_of :hashed_token, with: HASHED_TOKEN_PATTERN, allow_nil: true

  # Public: String description of this access (used for personal access tokens)
  # column :description
  validates_presence_of :description, if: :personal_access_token?
  # https://github.com/github/special-projects/issues/801
  validates_uniqueness_of :description, scope: [:user_id, :application_id, :fingerprint], case_sensitive: false, if: -> { T.bind(self, OauthAccess); personal_access_token? && GitHub::UTF8.valid_unicode3?(description.to_s) }
  validates :description, length: { maximum: 255 }, unicode3: true, if: :personal_access_token?
  validate :restrict_description_with_token_prefix, if: :personal_access_token?

  # All PATs must have a unique authorization. However, we allow `nil` until all
  # existing PATs have been backfilled.
  validates_uniqueness_of :authorization_id, if: :personal_access_token?, allow_nil: true

  # Public: String fingerprint helps OAuth applications distinguish between
  # multiple authorizations for a user for a given app. It is used mostly for
  # desktop/mobile applications that create multiple tokens for a single user,
  # where each token is used on a different physical device that the user owns.
  # column :fingerprint
  before_validation :set_fingerprint
  validates_uniqueness_of :fingerprint, allow_nil: true,
    scope: [:user_id, :application_id], case_sensitive: false

  validates :installation_type, inclusion: VALID_INSTALLATION_TYPES, allow_nil: true

  after_commit :instrument_creation, on: :create

  # NOTE: Due to the usage of scopes_changed? in the callback which delegates to
  # a serialized column, commit callbacks can't be used.
  before_update :instrument_update # rubocop:disable GitHub/AfterCommitCallbackInstrumentation

  after_commit :instrument_deletion, on: :destroy

  after_commit :sync_oauth_application_rate_limit_on_create, on: :create
  after_commit :sync_oauth_application_rate_limit_on_destroy, on: :destroy

  validate :scopes_are_allowed
  validate :matches_authorization, if: :authorization

  after_validation :translate_errors

  before_create :create_authorization
  before_create :limit_accesses_for_authorization_for_oauth_app, if: :oauth_application_type?
  before_create :limit_accesses_for_authorization_for_integration, if: :integration_application_type?
  before_save :update_authorization, if: :authorization
  before_validation :update_last_issued_at, if: :hashed_token_changed?

  validate :ensure_integration_capabilities, if: :installation
  validate :expiration_is_allowed_by_enterprise_policy, if: -> (token) { token.personal_access_token? && token.expires_at_timestamp_changed? && token.expiration_change_in_future? }, on: [:create, :update]

  after_save :destroy_active_credential_authorizations, if: :personal_access_token?
  after_destroy :destroy_authorization, if: :authorization

  # Resolves the application ID
  # in Ruby first, then queries oauth_accesses with literal IDs.
  # Returns an Array of OauthAccess records, loading in batches to avoid
  # large IN clauses when many applications match a given client_id.
  def self.for_client_id(client_id)
    if client_id == OauthApplication::PERSONAL_TOKENS_CLIENT_ID
      where(application_id: OauthApplication::PERSONAL_TOKENS_APPLICATION_ID).to_a
    elsif Integration.client_id?(client_id)
      app_ids = Integration.where(key: client_id).pluck(:id)
      load_for_app_ids_in_batches(Integration.name, app_ids)
    else
      app_ids = OauthAccessTokens.domain.oauth_applications.ids_for_keys(client_id)
      load_for_app_ids_in_batches(OauthApplication.name, app_ids)
    end
  end

  def self.load_for_app_ids_in_batches(app_type, app_ids)
    app_ids.each_slice(TOKEN_BATCH_SIZE).flat_map do |batch|
      where(application_type: app_type, application_id: batch).to_a
    end
  end
  private_class_method :load_for_app_ids_in_batches

  # Access tokens associated with the generic personal token application id.
  scope :personal_tokens, -> { where(application_id: OauthApplication::PERSONAL_TOKENS_APPLICATION_ID) }

  # OAuth accesses for applications that are GitHub Apps
  # (excludes those for OAuth Applications and personal tokens)
  scope :github_apps, -> {
    where(application_type: "Integration").where.not(application_id: OauthApplication::PERSONAL_TOKENS_APPLICATION_ID)
  }

  # Public: Serialized attributes
  # column :raw_data
  serialize_with_coder :raw_data, Coders::OauthAccessCoder

  # serialize_with_coder delegates the following to raw_data:

  # Public: String array of scopes this access has been granted.
  # array :scopes

  # Public: String array of scopes the application originally requested for
  # this access. If this value is not the same as :scopes, the user has
  # edited the oauth access request.
  # array :requested_scopes

  # Public: String informational note (used for personal access tokens) about
  # this access.
  # string :note

  # Public: String Stores the callback_url used to create this OAuth Access.
  # string :requested_redirect_uri

  # Public: String information note url (used for tokens created via the API)
  # about this access.
  # string :note_url

  delegate :scopes_changed?, to: :raw_data

  # Public: Generate a new random code for the access.
  #
  # Returns a String.
  def self.random_code
    SecureRandom.hex(CODE_BYTES)
  end

  def self.hash_token(token)
    HASHED_TOKEN_DIGEST.base64digest(token)
  end

  # Public: Generates a new random token pair, unhashed and hashed.
  #
  # Returns base64 String and base64 hashed version of the first String.
  def generate_random_token_pair
    random_token = SecureRandom.alphanumeric(TOKEN_BYTES)
    full_token = token_prefix + random_token + OauthAccess.checksum(random_token)
    [full_token, self.class.hash_token(full_token)]
  end

  # Public: Generates a new random token pair and sets `token_last_eight`
  #         and `hashed_token` of this instance with the results.
  #
  # Returns a base64 String (the token)
  def set_random_token_pair
    token, hashed_token = generate_random_token_pair
    self.token_last_eight = token.last(8)
    self.hashed_token = hashed_token

    token
  end

  # Public: Indicates whether this is a personal access token.
  #
  # Returns a Boolean.
  def personal_access_token?
    application_id == OauthApplication::PERSONAL_TOKENS_APPLICATION_ID
  end

  sig do
    params(
      created_by: T.any(Date, Time, ActiveSupport::TimeWithZone),
      expires_at_timestamp: T.nilable(Integer),
      created_at: T.any(Date, Time, ActiveSupport::TimeWithZone),
      is_personal_access_token: T::Boolean,
      scopes: T.nilable(T::Array[String])
    ).returns(T::Boolean)
  end
  def self.personal_access_token_eligible_for_account_recovery?(created_by:, expires_at_timestamp:, created_at:, is_personal_access_token:, scopes:)
    unexpired_access = expires_at_timestamp.nil? || expires_at_timestamp > Time.current.to_i

    is_personal_access_token &&
      unexpired_access &&
      created_at <= created_by &&
      !scopes.nil? &&
      scopes.include?("repo")
  end

  # Public: Indicates whether this is a a personal access token that can be used for account recovery.
  #
  # created_by        - Date by which the token must be created, to be eligible
  #
  # Returns a Boolean.
  sig { override.params(created_by: T.any(Date, Time, ActiveSupport::TimeWithZone)).returns(T::Boolean) }
  def personal_access_token_eligible_for_account_recovery?(created_by)
    self.class.personal_access_token_eligible_for_account_recovery?(created_by: created_by,
      expires_at_timestamp: expires_at_timestamp, created_at: T.must(created_at),
      is_personal_access_token: personal_access_token?, scopes: scopes)
  end

  sig { params(application_id: T.nilable(Integer)).returns(Integration) }
  def self.fallback_integration(application_id:)
    Integration.new(id: application_id)
  end

  sig { params(description: T.nilable(String), note_url: T.nilable(String)).returns(OauthApplication) }
  def self.fallback_oauth_application(description:, note_url:)
    OauthApplication.default(description, note_url)
  end

  # Gets the attached application or a creates a 'default' application for its
  # `application_type` if it's missing.
  #
  # Returns an OauthApplication or Integration.
  def safe_app
    app = application if application_id.to_i > 0

    app || (@safe_app ||= begin
      case application_type
      when "Integration"
        self.class.fallback_integration(application_id: application_id)
      else
        self.class.fallback_oauth_application(description: description, note_url: note_url)
      end
    end)
  end

  # Public: Grants the given scopes for this OauthAccess.  Also resets the code
  # and clears token.
  #
  # scopes                     - String comma-separated scopes that were granted (optional).
  # requested_scopes           - String comma-separated scopes that were requested (optional).
  # integration_version_number - String version number of the GitHub App integration (optional).
  # requested_redirect_uri     - String redirect_uri that was requested (optional).
  # entry_point                - String entry point to log with Permissions changes
  # code_challenge             - String code challenge for PKCE (optional).
  #
  # Returns self (an OauthAccess).
  def grant(scopes = nil, requested_scopes = nil, integration_version_number = nil, requested_redirect_uri = nil, entry_point = nil, code_challenge = nil)
    ActiveRecord::Base.connected_to(role: :writing) do
      # Integration accesses do not have OAuth scopes, so we can skip
      # the setting of scopes
      unless self.integration_application_type?
        self.scopes = self.class.normalize_scopes(scopes, visibility: :all)
        self.requested_scopes = self.class.normalize_scopes(requested_scopes, visibility: :all)
      end

      self.code = self.class.random_code
      self.token_last_eight = nil
      self.hashed_token = nil
      self.integration_version_number = integration_version_number # won't be persisted to the database, we need this to correctly honor the user's choice of GitHub App permissions from the OAuth page
      self.requested_redirect_uri = requested_redirect_uri

      if safe_app.feature_flag_enabled_or_raise?(:oauth_pkce_check) || safe_app.feature_flag_enabled_or_raise?(:oauth_pkce_forensics) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
        self.code_challenge = code_challenge
      end
      @entry_point = entry_point
      clear_invalid_scopes
      save!

      # Track the GTIDs/timestamps of the writes we just made, keyed by the OAuth code. When the client exchanges this
      # code for a token (see OauthAccess::Provider#access_for_code), this lets DatabaseSelector decide whether a
      # replica is caught up enough to serve the read so we don't have to always go to the primary.
      if FeatureFlag.vexi.enabled?(:oauth_access_token_more_replica_reads, application, default: false)
        DatabaseSelector::LastOperations.from_oauth_code(self.code).store_latest_writes
      end
    end
    self
  end

  # Public: Set scopes for this token without resetting the token or code.
  #
  # new_scopes - String or Array of scopes (optional).
  #
  # Returns an OauthAccess.
  def set_scopes(new_scopes = nil)
    ActiveRecord::Base.connected_to(role: :writing) do
      self.requested_scopes = scopes unless self.requested_scopes
      self.scopes = self.class.normalize_scopes(new_scopes, visibility: :all)
      clear_invalid_scopes
      save!
    end

    self
  end

  # Public: Return the list of scopes as a sorted, comma-separated String.
  #
  # Returns a String.
  def scopes_string
    Array(scopes).map { |scope| scope.to_s }.sort.join(",")
  end

  # Public: Gets the full list of approved access levels.  Access levels are
  # just valid scopes as Strings.  Invalid scopes are safely ignored.
  #
  # Returns an Array of Strings.
  def access_level
    @access_level ||= access_level!
  end

  def access_level_set
    @access_level_set ||= Set.new(access_level)
  end

  def scopes?(*scopes)
    return false if self.scopes.nil?
    scopes.any? { |scope| access_level_set.include?(scope.to_s) }
  end

  # Public: Clear the authorization code on this access and sets a new token.
  # For the appropriate application, can optionally specify a custom symbol `expiry` duration, defined in ::TOKEN_EXPIRIES.
  #
  # Returns the token.
  def redeem(extended_expiry: false)
    ActiveRecord::Base.connected_to(role: :writing) do
      self.code = nil

      response = if token_refreshable?
        build_refresh_token
        new_refresh_token = T.must(refresh_token)

        custom_refresh_token_expiry = ::Apps::Privileged.property(:refresh_token_expiry, app: application)
        if custom_refresh_token_expiry
          new_refresh_token.expires_at = custom_refresh_token_expiry.from_now
        end

        # Explicitly save refresh_token to avoid the cross-cluster transaction when the access is saved
        new_refresh_token.save! if explicitly_save_refresh_token?
        token = reset_with_expiry(expires_at: expires_in(extended_expiry: extended_expiry).from_now)
        [token, new_refresh_token.token]
      else
        reset_token
      end

      response
    end
  end

  def reset_without_expiry
    token, hashed_token = generate_random_token_pair

    # Save this data for instrumentation.
    payload = {
      old_token_last_eight: self.token_last_eight,
      old_hashed_token: self.hashed_token
    }
    ActiveRecord::Base.connected_to(role: :writing) do
      last_operations = DatabaseSelector::LastOperations.from_token(token)
      self.token_last_eight = token.last(8)
      self.hashed_token = hashed_token

      clear_invalid_scopes

      # Attempting to gather information about intermittent uniqueness
      # constraint violations that cause our SLOs to flap:
      #
      # https://github.com/github/ecosystem-apps/issues/1278#issuecomment-809798852
      begin
        save!
      rescue ActiveRecord::ActiveRecordError => e
        GitHub.logger.info(
          "OauthAccess Errors: #{self.errors.full_messages.join(",")}",
          "gh.oauth_access.valid" => self.valid?,
        )
        raise e
      end

      last_operations.store_latest_writes
    end

    instrument_regenerate(payload)

    T.must(authorization).notify_owner_of_token_regeneration if personal_access_token?

    token
  end

  alias_method :reset_token, :reset_without_expiry

  # Public: Reset the authorization token on this access.
  #
  # Aims to eventually replace `reset_token` by accepting `expires_at` directly
  # Rather than bumping by a default amount. See #reset_token
  #
  # Returns String token.
  def reset_with_expiry(expires_at:)
    token, hashed_token = generate_random_token_pair

    # Save this data for instrumentation.
    payload = {
      old_token_last_eight: self.token_last_eight,
      old_hashed_token: self.hashed_token
    }
    ActiveRecord::Base.connected_to(role: :writing) do
      last_operations = DatabaseSelector::LastOperations.from_token(token)
      self.token_last_eight = token.last(8)
      self.hashed_token = hashed_token

      if token_refreshable?
        self.expires_at = expires_at
      end

      clear_invalid_scopes

      # Attempting to gather information about intermittent uniqueness
      # constraint violations that cause our SLOs to flap:
      #
      # https://github.com/github/ecosystem-apps/issues/1278#issuecomment-809798852
      begin
        save!
      rescue ActiveRecord::RecordNotUnique => e
        GitHub.logger.info(
          "OauthAccess Errors: #{self.errors.full_messages.join(",")}",
          "gh.oauth_access.valid" => self.valid?,
        )
        raise e
      end

      # When the token is redeemed for the first time
      # set the scoped installation to match the expiration
      # of the refresh token.
      if token_refreshable? && installation.present?
        installation.extend_expires_at(T.must(refresh_token).expires_at, entry_point: entry_point, token_last_eight: token_last_eight)
      end

      last_operations.store_latest_writes
    end

    instrument_regenerate(payload)
    T.must(authorization).notify_owner_of_token_regeneration if personal_access_token?
    token
  end

  def token_refreshable?
    if integration_application_type?
      application&.user_token_expiration_enabled?
    elsif personal_access_token?
      true
    else
      false
    end
  end

  def hashed_token(hex: false)
    return nil unless hashed_token = read_attribute(:hashed_token)
    hex ? Base64.decode64(hashed_token).unpack("H*").first : hashed_token
  end

  sig { params(scopes: T.nilable(T::Array[T.untyped])).returns(T::Array[String]) }
  def self.access_level_from(scopes)
    return [] if scopes.blank?
    accesses = []
    scopes.each do |scope|
      scope_s = scope.to_s
      accesses << scope_s if Api::AccessControl.acceptable_scopes.key?(scope_s)
    end
    accesses
  end

  def access_level!
    self.class.access_level_from(scopes)
  end

  # Public: Return a hexdigest of the user session and authenticating application.
  #
  # Returns a 64 character String token.
  def browser_session_id(user_session)
    return if personal_access_token?
    user_session.secret_hmac.update(application.key).hexdigest
  end

  # Public: Destroy access and instrument the deletion using the provided
  # explanation
  #
  # payload - Symbol of the explanation for deletion. All valid Symbols can be
  # found in OauthUtil::VALID_DESTROY_EXPLANATIONS. These symbols are mapped
  # to a more descriptive explanation that will be shown in the audit log.
  #
  # Returns the result of calling destroy() on the model instance.
  def destroy_with_explanation(explanation, entry_point:, skip_destroy_authorization: false)
    unless OauthUtil.destroy_explanation(explanation)
      raise ArgumentError, "invalid destroy explanation: #{explanation}"
    end
    @destroy_explanation = explanation
    destroy_with_args(entry_point:, skip_destroy_authorization:)
  end

  def expire(entry_point:)
    expiration = expires_at

    return if expiration.nil? || expiration > Time.current
    destroy_with_explanation(:expired, entry_point: entry_point)
  end

  def expires_in(extended_expiry: false)
    return DEFAULT_INSTALLATION_TOKEN_EXPIRY unless extended_expiry

    custom_expiry = ::Apps::Privileged.property(:oauth_access_expiry, app: application)
    custom_expiry || DEFAULT_INSTALLATION_TOKEN_EXPIRY
  end

  # Public: Revokes the personal access token and instruments the revocation
  # audit log using the provided reason.
  def revoke_personal_access_token!(reason:)
    unless personal_access_token?
      raise TypeError, "only personal access tokens can be revoked"
    end

    unless revoke_reason = OauthUtil.revoke_reason(reason)
      raise ArgumentError, "invalid revoke reason: #{reason}"
    end

    ActiveRecord::Base.connected_to(role: :writing) do
      self.expires_at = Time.current
      save!
    end

    GitHub.dogstats.increment("account_security.oauth_access", tags: ["reason:#{reason}", "action:revoke"])
    instrument_revoke({ reason: revoke_reason, explanation: revoke_reason })
  end

  include Instrumentation::Model

  # The user who performed the action as set in the GitHub request context. If the context doesn't
  # contain an actor, fallback to the user that the oauth authorization belongs to.
  def event_actor
    return @event_actor if defined?(@event_actor)
    @event_actor = if GitHub.context[:actor_id].present?
      Users.domain.by_id(GitHub.context[:actor_id])
    else
      user
    end
  end

  def event_prefix() :oauth_access end

  def set_destroy_explanation_for_cascade(explanation)
    unless OauthUtil.destroy_explanation(explanation)
      raise ArgumentError, "invalid destroy explanation: #{explanation}"
    end
    @destroy_explanation = explanation
  end

  def event_payload
    payload = {
      oauth_access_id: id,
      application_id: safe_app.id,
      application_name: safe_app.name,
      application_type: application_type,
      scopes: scopes,
      accessible_org_ids: accessible_organization_ids,
      token_last_eight: token_last_eight,
      hashed_token: hashed_token,
      token_id: id,
      token_scopes: scopes_string
    }

    user = self.user
    if user
      payload[T.cast(user, User).event_prefix] = user
    elsif user_id
      payload[:user_id] = user_id
    end

    if FeatureFlag.vexi.enabled?(:oauth_access_tokens_include_description_in_hydro_event, default: false)
      payload[:description] = description
    end

    if oauth_application_type?
      payload[:oauth_application_name] = safe_app.name
    end

    if integration_application_type?
      payload[:integration] = safe_app.name
    end

    payload
  end

  # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
  def accessible_organization_ids
    @accessible_organization_ids ||= if user
      if personal_access_token?
        # A PAT can access all orgs a user can access.
        T.cast(user, User).organization_ids
      else
        # Only log the organizations that an authorization can actually access.
        Organization.oauth_app_policy_met_by_filter(safe_app, T.cast(user, User).organization_ids)
      end
    end
  end
  # rubocop:enable GitHub/BooleanMemoizationWithOrOperator

  # Public: Instrument creating records.
  #
  # payload - Hash of custom payload data.
  #
  # Returns nothing.
  def instrument_creation(payload = {})
    instrument :create, payload.merge(expiration_audit_log_context)
    create_payload = {
      actor: user,
      oauth_access: self,
      app: safe_app,
      scopes: scopes,
      accessible_organization_ids: accessible_organization_ids,
    }
    if FeatureFlag.vexi.enabled?(:oauth_access_tokens_include_description_in_hydro_event, default: false)
      create_payload[:description] = description
    end
    GlobalInstrumenter.instrument "oauth_access.create", create_payload
  end

  # Public: Instrument updating records.
  #
  # payload - Hash of custom payload data.
  #
  # Returns nothing.
  def instrument_update(payload = {})
    if scopes_changed? || user_id_changed?
      instrument :update, payload
    end
  end

  # Public: Instrument regenerating the authorization token on this access.
  #
  # payload - Hash of custom payload data.
  #
  # Returns nothing.
  def instrument_regenerate(payload = {})
    instrument :regenerate, payload.merge(expiration_audit_log_context)

    GlobalInstrumenter.instrument "oauth_access.regenerate", {
      actor: user,
      oauth_access: self,
      app: safe_app,
      scopes: scopes,
      accessible_organization_ids: accessible_organization_ids,
    }
  end

  # Public: Instrument deleting records.
  #
  # extra_payload - Hash of custom payload data.
  #
  # Returns nothing.
  def instrument_deletion(extra_payload = {}, user: self.user)
    if event_actor&.employee? && event_actor != user
      actor_hash = GitHub.guarded_audit_log_staff_actor_entry(event_actor)
      extra_payload = extra_payload.merge(actor_hash)
    end

    instrument :destroy, extra_payload.merge(explanation: destroy_explanation_for_audit_log)

    GlobalInstrumenter.instrument "oauth_access.delete", {
      actor: user,
      oauth_access: self,
      app: safe_app,
      scopes: scopes,
      accessible_organization_ids: accessible_organization_ids,
    }
    explanation_key = @destroy_explanation || "none"
    GitHub.dogstats.increment("account_security.oauth_access", tags: ["explanation:#{explanation_key.to_s.gsub(/_/, "-")}", "action:destroy"])
  end

  sig { params(user: User).void }
  def instrument_destroy_for_parent_destroy(user:)
    instrument_deletion({ user: user }, user: user)
  end

  # Sync enterprise limit data to authnd cluster when an OAuth token is created.
  # Only applies to OAuth application tokens (not PATs or GitHub App tokens).
  def sync_oauth_application_rate_limit_on_create
    return unless oauth_application_type?
    return unless FeatureFlag.vexi.enabled?(:authnd_oauth_enterprise_limits, default: false)

    OauthEnterpriseLimitJob.perform_later(app_id: application_id, user_id:)
  end

  # Remove enterprise limit data when an OAuth token is destroyed.
  # Only removes if no other active tokens exist for this app/user pair.
  def sync_oauth_application_rate_limit_on_destroy
    return unless oauth_application_type?
    return unless FeatureFlag.vexi.enabled?(:authnd_oauth_enterprise_limits, default: false)

    remaining = OauthAccess.where(
      application_id:,
      application_type: "OauthApplication",
      user_id:,
    ).where.not(id:).exists?

    return if remaining

    OauthEnterpriseLimitJob.perform_later(app_id: application_id, user_id:, action: "remove")
  end

  def note
    description || raw_data.note
  end

  def note=(value)
    write_attribute :description, value
  end

  def destroy_explanation_for_audit_log
    if @destroy_explanation == :revocation_api
      OauthUtil.destroy_explanation(@destroy_explanation)
    else
      @destroy_explanation
    end
  end

  # Window of time between access logs writes.
  #
  # Returns a duration.
  ACCESS_THROTTLING = 1.week
  ACCESS_CUTOFF_DATE = Time.utc(2014, 3, 6)

  # Public: Register this oauth access token has been used
  #
  # This only updates the timestamp within an interval to prevent a lot
  # of writes if used often in a short period of time.
  #
  # Returns nothing
  def bump
    time = Time.now
    return if bumped_within_throttling_period?(time)
    return unless persisted?

    if GitHub.cache.add(last_accessed_memcache_key, time, ACCESS_THROTTLING.to_i)
      if FeatureFlag.vexi.enabled?(:oauth_access_token_job_enqueue, default: false)
        # Redis-backed dedup (SET NX EX) as a secondary layer, preventing
        # job queue storms if Memcached goes cold.
        OauthAccessBumpJob.enqueue_once_per_interval(
          args: [T.must(id), time.to_i],
          interval: ACCESS_THROTTLING.to_i,
          run_at_beginning_of_interval: true,
          unique_id: id.to_s,
        )
      else
        OauthAccessBumpJob.perform_later(T.must(id), time.to_i)
      end
    end
  end

  def bump!(time)
    return if bumped_within_throttling_period?

    ActiveRecord::Base.connected_to(role: :writing) do
      threshold = ACCESS_THROTTLING.ago.to_formatted_s(:db)
      self.class.connection.update(Arel.sql(<<-SQL, id: id, accessed_at: time, threshold: threshold))
        UPDATE oauth_accesses SET accessed_at = :accessed_at
        WHERE id = :id AND (accessed_at < :threshold OR accessed_at IS NULL)
      SQL
    end

    authorization&.bump(time)

    nil
  end

  # Public: Has this access been bumped in the access throttling period.
  #
  # now - The time to use to determine the end of the throttling period.
  #
  # Returns true if bumped within period else false.
  def bumped_within_throttling_period?(now = Time.now)
    return false unless accessed_at

    T.must(accessed_at) > (now - ACCESS_THROTTLING)
  end

  def last_accessed_memcache_key
    "oauth_accesses:last_accessed:#{id}"
  end

  def last_access_time
    accessed_at&.in_time_zone
  end

  def last_access_date
    last_access_time&.to_date
  end

  def integration_application_type?
    application_type == "Integration"
  end

  def oauth_application_type?
    application_type == "OauthApplication" && !personal_access_token?
  end

  sig { params(is_personal_access_token: T.nilable(T::Boolean)).returns(T.nilable(ProgrammaticAccessTokenType)) }
  def self.programmatic_access_token_type(is_personal_access_token:)
    return unless is_personal_access_token
    ProgrammaticAccessTokenType::Classic
  end

  def pat_type
    self.class.programmatic_access_token_type(is_personal_access_token: personal_access_token?)
  end

  def pat_type_name
    pat_type&.name
  end

  def ability_delegate
    authorization
  end

  def async_ability_delegate
    async_authorization
  end

  sig do
    params(
      is_personal_access_token: T.nilable(T::Boolean),
      application: T.nilable(T.any(Integration, OauthApplication))
    ).returns(T::Boolean)
  end
  def self.saml_enforceable?(is_personal_access_token:, application:)
    is_personal_access_token || Apps::Privileged.capable?(:saml_sso_required, app: application)
  end

  def saml_enforceable?
    self.class.saml_enforceable?(is_personal_access_token: personal_access_token?, application: application)
  end

  def expired?
    expiration = expires_at

    return false if expiration.nil?
    unless token_refreshable?
      # There should never be a case where the token is expired and not refreshable.
      # We need to check how often this happens and stat it.
      unless expiration > Time.now
        GitHub.dogstats.increment("oauth_access", tags: ["action:expired_and_not_refreshable"])
        GitHub.logger.info("Bug - oauth access expired and not refreshable", {
          "gh.oauth_access.expires_at" => expiration,
          "gh.oauth_access.id" => id,
          "gh.oauth_access.type" => application_type,
          "gh.oauth_access.user_id" => user_id,
          "gh.oauth_access.application.id" => application_id,
          "gh.oauth_access.installation.id" => installation_id,
          "gh.oauth_access.installation.type" => installation_type,
        })
      end
      return false
    end

    !(expiration > Time.now)
  end

  def expires_soon?
    expiration = expires_at

    return false if expiration.nil?
    return false unless token_refreshable?

    expiration.between?(Time.now, Time.now + 3.days)
  end

  # Public: Whether the pending expiration change sets the token to expire in
  # the future (or to never expire).
  #
  # The enterprise lifetime-limit policy only needs to be enforced when a PAT's
  # expiration is newly set or pushed further out. Revoking a
  # token moves `expires_at` to the current time (or earlier), which can never
  # exceed a max-lifetime policy, so those changes should not be validated.
  #
  # A nil `expires_at` means the token never expires (the longest possible
  # lifetime) and must always be validated.
  #
  # Returns a Boolean.
  def expiration_change_in_future?
    # When the flag is disabled, preserve the original behavior of validating
    # on any expiration change (including revoking/shortening).
    return true unless FeatureFlag.vexi.enabled?(:classic_pat_skip_expiration_validation_on_revoke, default: false)

    timestamp = expires_at_timestamp
    return true if timestamp.nil?

    timestamp > Time.current.to_i
  end

  # Public: Destroys the OAuth access and propagates kwargs to AR callback methods
  #
  # callback_args - keyword arguments to propagate to AR callback methods
  def destroy_with_args(**callback_args)
    @callback_args = callback_args
    self.destroy
  end

  # Public: Enable the domain orchestration bypass for this record.
  # When set, the create_authorization and access-limiting before_create callbacks are skipped,
  # and the domain orchestrator (OauthAccessTokens::Domain#grant) handles Steps 1-5 explicitly.
  # The legacy Provider#grant path is unaffected. Only called by the orchestrator.
  def delegate_to_domain_interface!
    @delegate_to_domain_interface = true
  end

  def delegate_to_domain_interface?
    !!@delegate_to_domain_interface
  end

  private

  # Private: Instrument revoking a record.
  #
  # payload - Hash of custom payload data.
  #
  # Returns nothing.
  def instrument_revoke(payload = {})
    instrument :revoke, payload.merge(
      actor: GitHub.ghost_user_login,
    )
  end

  def clear_invalid_scopes
    self.scopes = self.class.valid_scopes(scopes)

    valid_hidden_scopes = self.class.valid_hidden_scopes(user)
    self.scopes.reject! { |scope| valid_hidden_scopes[scope] == false }
  end

  def scopes_are_allowed
    bad_scopes = self.class.invalid_scopes(scopes)

    valid_hidden_scopes = self.class.valid_hidden_scopes(user)
    bad_scopes += Array(scopes).select { |scope| valid_hidden_scopes[scope] == false }

    if !bad_scopes.blank?
      errors.add :scopes, "are invalid: #{bad_scopes.to_sentence}"
    end
  end

  def owner_is_human
    return if user.blank?

    errors.add :user, "must be a human" unless T.must(user).user?
  end

  def owner_meets_email_verification_requirements
    return unless user
    return if Apps::Privileged.capable?(:skip_oauth_user_eligibility_check, app: application)
    GitHub.dogstats.increment "oauth_access", tags: ["action:email-verification", "valid:true", "user_signup_timeframe:#{T.cast(user, User).signup_timeframe}"]
    if T.cast(user, User).must_verify_email?
      OauthAccessTokens::Domain.instrument_email_verification_required(user: T.must(user), application_id: application_id)
      errors.add :user, "must have a verified email address in order to authenticate via OAuth"
    end
  end

  def set_fingerprint
    # If fingerprint is "" then saving the column as NULL is better for allowing
    # DB enforced uniqueness constraints.
    write_attribute(:fingerprint, fingerprint.blank? ? nil : fingerprint)
  end

  def token_prefix
    if personal_access_token?
      PAT_PREFIX
    elsif integration_application_type?
      USER_TO_SERVER_PREFIX
    else
      OAUTH_PREFIX
    end
  end

  def create_authorization
    return if delegate_to_domain_interface?

    options = {
      user: user,
      scopes: scopes,
      entry_point: entry_point,
    }

    if integration_application_type?
      options[:integration_version_context] = if FeatureFlag.vexi.enabled?(:oauth_access_create_authorization_domain_version_context, user, default: false)
        OauthAccessTokens.domain.build_integration_version_context(user: T.cast(T.must(user), User), application: application, target_version_number: integration_version_number&.to_i)
      else
        build_integration_version_context(integration_version_number)
      end
    end

    if personal_access_token?
      options[:description] = description
      options[:is_personal_access_token] = true
    else
      options[:application] = application
    end

    options[:entry_point] = entry_point if entry_point

    result = OauthAuthorization::Creator.perform(**options)

    if result.success?
      version_reconciler = OauthAuthorization::VersionReconciler.new(
        result.authorization,
        user: user,
        entry_point: entry_point,
        integration_version_context: options[:integration_version_context]
      )

      version_reconciler.perform

      self.authorization = result.authorization
    else
      errors.add(:authorization, result.error)
    end
  end

  # A stop-gap solution to the problem of cross-domain queries against
  # `integration_versions` originating from transactions on
  # `oauth_authorizations`.
  #
  # Superseded by OauthAccessTokens::Domain#build_integration_version_context.
  # Will be removed when callback bypass is active (Sub-Issue 7, authentication#6794).
  #
  # TODO: Extract this behind a suitable domain interface on OauthAccessTokens
  # and/or IntegrationVersions.
  def build_integration_version_context(target_version_number)
    return {} unless integration_application_type?

    access_user = user
    return {} unless access_user

    current_oauth_authorization = T.cast(access_user, User).oauth_authorizations.where(
      application_id: application.id,
      application_type: "#{application.class}"
    ).first

    latest = application.latest_version
    target = application.versions.find_by(number: target_version_number) || latest
    current =
      if current_oauth_authorization.present?
        application.versions.find_by(number: current_oauth_authorization.integration_version_number) || latest
      else
        target
      end

    {
      current_version: OauthAuthorization::VersionContext.new(
        default_content_references: current.default_content_references,
        default_events: current.default_events,
        default_permissions: current.default_permissions,
        number: current.number,
        single_file_paths: current.single_file_paths,
        user_permissions: current.user_permissions,
      ),
      target_version: OauthAuthorization::VersionContext.new(
        default_content_references: target.default_content_references,
        default_events: target.default_events,
        default_permissions: target.default_permissions,
        number: target.number,
        single_file_paths: target.single_file_paths,
        user_permissions: target.user_permissions,
      ),
      latest_version: OauthAuthorization::VersionContext.new(
        default_content_references: latest.default_content_references,
        default_events: latest.default_events,
        default_permissions: latest.default_permissions,
        number: latest.number,
        single_file_paths: latest.single_file_paths,
        user_permissions: latest.user_permissions,
      )
    }
  end

  # See https://github.com/github/github/issues/21704 for context
  def translate_errors
    if self.errors.include?(:description)
      errors.details[:description].each do |description_error|
        reason = description_error.delete(:error)

        self.errors.add(:note, reason, **description_error)
      end
      # We cannot call `self.errors.delete(:description)` because this will attempt to return the translation,
      # which will raise an exception as it is not defined.
      self.errors.where(:description).each { |error| self.errors.errors.delete(error) }
    end
  end

  def update_authorization
    return unless self.authorization
    current_authorization = T.must(self.authorization)

    # A PAT can only ever have one set of scopes. So, we replace the
    # authorization's scopes entirely.
    if personal_access_token? && scopes_changed?
      current_authorization.scopes = nil
      current_authorization.add_scopes(scopes)
    # Third-party accesses can each have their own set of scopes, so we
    # add the scopes for this access to the authorization.
    elsif scopes_changed?
      current_authorization.add_scopes(scopes)
    end

    if personal_access_token? && description_changed?
      current_authorization.description = description
    end

    current_authorization.save! if current_authorization.changed?
  end

  # Private: callback to destroy associated organization credential
  # authorizations that have not been revoked.
  #
  # Only destroy "active" credential authorizations because revoked records act
  # as a denylist maintained by the owners of an organization.
  def destroy_active_credential_authorizations
    credential_authorizations.active.destroy_all
  end

  # Private: Deletes associated OauthAuthorization if the authorization has no
  # remaining authorized objects (public keys and accesses).
  #
  # Returns nothing.
  def destroy_authorization
    return if defined?(@callback_args) && !!@callback_args[:skip_destroy_authorization]
    return unless self.authorization
    current_authorization = T.must(self.authorization)

    # If we are being destroyed due to an association :dependent => :destroy
    # then there is no need for us to destroy our parent OauthAuthorization.
    return if destroyed_by_association&.active_record == OauthAuthorization
    # We delete the associated authorization if all resources associated with
    # the authorization have been removed (i.e. unused) or if we are destroying
    # a personal access token. Unlike regular OAuth authorizations, personal
    # access tokens always only have a single token and all resources associated
    # with the token should be destroyed when the token is destroyed.
    return unless personal_access_token? || current_authorization.unused?
    entry_point = (defined?(@callback_args) && @callback_args[:entry_point]) || :unknown_oauth_access_destroy_authorization
    if @destroy_explanation.present?
      current_authorization.destroy_with_explanation(@destroy_explanation, entry_point: entry_point)
    else
      current_authorization.destroy_with_args(entry_point: entry_point)
    end
  end

  def matches_authorization
    if user != T.must(authorization).user
      errors.add :user_id, "must be the same user as associated authorization"
    elsif application != T.must(authorization).application
      errors.add :application_id, "must be the same user as associated authorization"
    end
  end

  # Private: Determines which access to delete based on usage and creation time.
  #
  # accesses - Collection of OauthAccess records to choose from.
  #
  # Returns the OauthAccess that should be deleted, or nil if none found.
  def find_least_recently_accessed(accesses)
    if FeatureFlag.vexi.enabled?(:prevent_new_token_deletion, default: false)
      creation_time_cutoff = NEW_TOKEN_DELETION_BUFFER.ago
      unused_accesses = accesses.select { |access| access.accessed_at.nil? && access.created_at <= creation_time_cutoff }

      # We destroy unused accesses when possible. And, if there is
      # more than one unused access, we destroy the oldest one.
      # If no unused accesses exist (or all are protected by the buffer),
      # fall back to deleting the least recently used access, or if all
      # are unused, the oldest by created_at.
      least_recently_used = if unused_accesses.present?
        unused_accesses.min_by(&:created_at)
      else
        accesses.min_by(&:created_at)
        used_accesses = accesses.reject { |access| access.accessed_at.nil? }
        if used_accesses.present?
          used_accesses.min_by(&:accessed_at)
        else
          # All accesses are unused, delete the oldest by created_at
          accesses.min_by(&:created_at)
        end
      end
    else
      # Unflagged, old behavior
      unused_accesses = accesses.select { |access| access.accessed_at.nil? }
      if unused_accesses.present?
        unused_accesses.min_by { |access| T.cast(access.created_at, ActiveSupport::TimeWithZone) }
      else
        accesses.min_by { |access| T.cast(access.accessed_at, ActiveSupport::TimeWithZone) }
      end
    end
  end

  # Private: Deletes the least recently used access if the currently created
  # access exceeds OauthAuthorization::MAXIMUM_ACCESSES_FOR_APP. We do this to
  # prevent an unbounded number of accesses from being created over time.
  #
  # Returns nothing
  def limit_accesses_for_authorization_for_oauth_app
    return if delegate_to_domain_interface?

    # We differentiate between accesses with unique scopes so that accesses for
    # different uses do not evict each other.
    normalized_scopes = self.class.normalize_scopes(scopes)
    accesses = T.must(authorization).accesses.select do |access|
      self.class.normalize_scopes(access.scopes) == normalized_scopes
    end

    # Temporarily support application specific limit overrides.
    maximum_accesses = maximum_accesses_for_application

    return unless accesses.count >= maximum_accesses

    least_recently_accessed = find_least_recently_accessed(accesses)
    # TODO: Monitor the entry point data and see if we need to push this
    # further up the stack.
    least_recently_accessed&.destroy_with_explanation(:max_for_app, entry_point: :limit_accesses_for_authorization_for_oauth_app)
  end

  # Private: Deletes the least recently used access if the currently created
  # access exceeds the limit appropriate for the Integration.
  #
  # For integrations opted in to expiring tokens
  #   OauthAuthorization::MAXIMUM_ACCESSES_FOR_EXPIRING_APP.
  #
  # For integrations not opted in to expiring tokens
  #   OauthAuthorization::MAXIMUM_ACCESSES_FOR_APP.
  #
  # We do this to prevent an unbounded number of accesses from being created over time.
  #
  # Returns nothing
  def limit_accesses_for_authorization_for_integration
    return if delegate_to_domain_interface?

    # Find accesses where a scoped installation is not bound to the record.
    # See https://github.com/github/github/pull/140107 for more details.
    accesses = T.must(authorization).accesses.where(installation: nil)
    maximum_accesses = maximum_accesses_for_integration

    total_accesses = ActiveRecord::Base.connected_to(role: :reading) { accesses.count }

    return unless total_accesses >= maximum_accesses

    least_recently_accessed = find_least_recently_accessed(accesses)
    # TODO: Monitor the entry point data and see if we need to push this
    # further up the stack.
    least_recently_accessed&.destroy_with_explanation(:max_for_app, entry_point: :limit_accesses_for_authorization_for_integration)
  end

  def maximum_accesses_for_application
    return default_access_limit unless GitHub.oauth_access_limit_overrides_enabled?

    if application&.feature_flag_enabled_or_raise?(:oauth_access_limit_property_override) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
      Apps::Privileged.property(:oauth_access_limit, app: application) || default_access_limit
    else
      # TODO: Remove me when oauth_access_limit_property_override is shipped.
      # Old behavior, using hard-coded App IDs in this file.
      MAXIMUM_ACCESSES_FOR_APP_OVERRIDES.fetch(
        T.must(authorization).application_id,
        default_access_limit,
      )
    end
  end

  def maximum_accesses_for_integration
    return default_access_limit unless GitHub.oauth_access_limit_overrides_enabled?

    if application&.feature_flag_enabled_or_raise?(:oauth_access_limit_property_override) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
      Apps::Privileged.property(:oauth_access_limit, app: application) || default_access_limit
    else
      # TODO: Remove me when oauth_access_limit_property_override is shipped.
      # Old behavior, using hard-coded App IDs in this file.
      return default_access_limit unless MAXIMUM_ACCESSES_FOR_APP_OVERRIDES.keys.include?(application&.id)

      # TODO: Remove me when we've proved that the privileged apps property
      # configured for Coding Agent is working as expected.
      if T.must(authorization).application_id == COPILOT_CODING_AGENT_APPLICATION_ID &&
          user&.feature_flag_enabled_or_raise?(:copilot_coding_agent_access_limit_overrides_upgrade) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
        return 100
      end

      MAXIMUM_ACCESSES_FOR_APP_OVERRIDES.fetch(
        T.must(authorization).application_id,
        default_access_limit,
      )
    end
  end

  def default_access_limit
    case application
    when Integration then token_refreshable? ? MAXIMUM_ACCESSES_FOR_EXPIRING_APP : MAXIMUM_ACCESSES_FOR_APP
    else MAXIMUM_ACCESSES_FOR_APP
    end
  end

  def ensure_integration_capabilities
    return errors.add(:installation, "cannot be set for an OauthApplication") unless integration_application_type?

    unless installation.integration_id == application_id
      errors.add(:installation, "installation does not belong to the Integration")
    end
  end

  def expiration_audit_log_context
    return {} unless token_refreshable?

    preset_selection = TokenExpirable::VALID_DEFAULT_EXPIRATIONS[self.default_expires_at]&.to_s
    expiration = T.unsafe(self).expires_at

    {
      expires_at_preset: preset_selection,
      expires_at: expiration,
      expires_at_custom_date: self.custom_expires_at
    }
  end

  def restrict_description_with_token_prefix
    return unless description.present?

    if T.must(description).include?(PAT_PREFIX)
      errors.add(:description, :github_token_prefix)
    end
  end

  def destroy_installation
    associated_installation = with_read { installation }
    associated_installation&.destroy
  end

  def explicitly_save_refresh_token?
    FeatureFlag.vexi.enabled?(:explicitly_save_refresh_token, default: false)
  end

  def update_last_issued_at
    self.last_issued_at = Time.current
  end

  def target_enforces_expiration_limit?
    target_expiration_limit_enforcer.present?
  end

  def target_expiration_limit_enforcer
    return unless user

    token_user = T.cast(user, User)
    ProgrammaticAccessTokenLifetimeConfiguration.limit_enforcer_for(token_user)
  end

  def expiration_exceeds_target_limit?(lifetime_config)
    return false if lifetime_config.exempted_for?(user)
    expiration_limit = lifetime_config.expiration_limit
    return false if expiration_limit.nil?

    pat_lifetime_in_days == :unlimited || pat_lifetime_in_days > expiration_limit
  end

  def expiration_is_allowed_by_enterprise_policy
    enterprise = target_expiration_limit_enforcer
    return unless enterprise

    lifetime_config = ProgrammaticAccessTokenLifetimeConfiguration.new(enterprise, ProgrammaticAccessTokenType::Classic)
    return unless expiration_exceeds_target_limit?(lifetime_config)
    errors.add(:base, :invalid_expiration, message: "Your enterprise does not allow tokens to be created with expiration above #{lifetime_config.expiration_limit} days")
  end
end
