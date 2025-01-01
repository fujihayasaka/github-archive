# typed: true
# frozen_string_literal: true

require "base64"
require "digest/sha2"
require "openssl"
require "securerandom"

class UserSession < ApplicationRecord::Domain::Users
  include GitHub::FlipperActor
  include GitHub::VexiActor
  include Instrumentation::Model
  include GitHub::Relay::GlobalIdentification

  SUDO_EXPIRY = 2.hours

  # Byte size of client's private key.
  #
  # 36 bytes was arbitrarily choosen by @mastahyeti and @josh when 32 would
  # have probably done.  This key size does not change and represents the number
  # of bytes passed to a url safe random key generator, which will return a
  # random key of the 48 characters.
  KEY_SIZE = 36

  # Size of key when urlsafe Base64'd generated from SecureRandom.urlsafe_base64(KEY_SIZE)
  # This base64 key size represents a randomly generated portion on a key,
  # which is a standard base64 key size for dotcom and GHES users.
  # When the key is generated fo EMU based users it will be larger since it will contain
  # an appended business shortcode.  The key is the user_session key that is stored
  # in a cookie and validated against the hashed one stored in the DB.  The length of
  # a base64 key for an EMU can vary since the business shortcode can be between 3 and 9
  # characters long, plus 1 for the underscore.
  BASE64_KEY_SIZE = 48

  # Pattern to validate incoming Base64'd keys
  BASE64_KEY_RE = /\A[A-Za-z0-9\-_=]{#{BASE64_KEY_SIZE}}\z/
  # Pattern to validate incoming keys (accepts keys either without a business shortcode suffix, or with a _valid_ business shortcode suffix
  BASE64_KEY_WITH_SHORTCODE_RE = /\A([A-Za-z0-9\-_=]{#{BASE64_KEY_SIZE}}){1}(_{1}[a-zA-Z0-9]{3,9})?\z/

  # Use SHA256 for hashing keys
  HASHED_KEY_DIGEST = Digest::SHA256

  # Require hashed key to be a 44 char base64 string
  HASHED_KEY_RE = /\A[A-Za-z0-9+\/=]{44}\z/

  # Number of random bytes for secret token
  SECRET_BYTES = 32

  # Require secret token to be a 44 char base64 string
  SECRET_RE = /\A[A-Za-z0-9+\/=]{44}\z/

  # Digest to use for any HMAC signed by the secret
  SECRET_HMAC_DIGEST = OpenSSL::Digest::SHA256

  # Number of random bytes for CSRF token
  CSRF_BYTES = 32

  # Require CSRF token to be a 44 char base64 string
  CSRF_TOKEN_RE = /\A[A-Za-z0-9+\/=]{44}\z/

  # Window of time between bumping sudo_enabled_at.
  #
  # Returns a duration.
  SUDO_THROTTLING = 10.minutes

  # Window of time between updating changes in IP
  IP_CHANGE_THROTTLING = 5.minutes

  # Minimum window of time between when in_use can be updated on a session for
  # normal GET requests.  This does not apply to session management events like
  # login, adding accounts, or switching accounts.
  #
  # This is largely a safety measure to prevent DB writes as part of GET requests due to the
  # mark_in_use fallback.  This should only happen in limited cases:
  # - grandfathered user_sessions (using the account switcher) prior to the introduction of in_use (~100 sessions total)
  # - users who manually copy their cookies between different browsers, which is additionally throttled 1-to-1 by switching session.
  IN_USE_THROTTLING = 5.seconds

  # How long impersonated sessions should last for.
  #
  # Since these sessions are only temporarily granted to staff to investigate
  # issues, they are short lived compared to regular sessions.
  #
  # Returns a duration.
  IMPERSONATED_EXPIRES = 1.hour

  # For how long sessions should be considered recent.
  #
  # Returns a duration.
  RECENTNESS = 24.hours

  # The number of simultaneous active user sessions a user is allowed.
  LIMIT = 100

  # The number of simultaneous active user sessions a user can have before we
  # enforce the limit.
  #
  # This threshold is distinct from the LIMIT so that we don't trigger
  # enforcement for every new session but allow several to accrue. For some
  # automated users, this is essential to not create a large volume of jobs
  # and database queries.
  LIMIT_ENFORCEMENT_THRESHOLD = 500

  # Reasons why a session is revoked.
  #
  # Returns an Array of String revoke reason identifiers.
  VALID_REVOKE_REASONS = [
    # User explicitly clicked "Sign out"
    "logout",

    # User remotely revoke one of their other sessions from the
    # "Security History" page.
    "user_remote_revoke",

    # When user changes their password, all their other active sessions are
    # revoked.
    "password_changed",

    # The user is deleting their account
    "account_destroy",

    # When staff user switches back to their normal account, the impersonated
    # session is revoked.
    "unimpersonate",

    # A bit of an edge case. If the user logins in or signs up for a new
    # account while they are already signed in as another user.
    "legacy_switched_users",

    # For special occasions, when we need to do mass revocation.
    "security_incident",

    # SAML identity provider session expired.
    "saml_expired",

    # Revoke active sessions when a User is suspended.
    "suspended",

    # Authentication changed by administrator.
    "authentication_switch",

    # Previously grouped under "password_change", this is an actual email-based reset
    "password_reset",

    # Previously grouped under "password_change", this password was randomized by staff
    "password_randomized",

    # A session was detected as compromised (e.g. Spycloud data set, #security-4271).
    "compromised_session",

    # External identity session was revoked/destroy for EMU
    "emu_session_revoked",
  ]

  # http://heartbleed.com/
  HEARTBLEED_INCIDENT = Time.new(2014, 4, 8)

  belongs_to :user
  belongs_to :impersonator, class_name: "User"
  belongs_to :impersonator_session, class_name: "UserSession"

  has_many :external_identity_sessions, dependent: :destroy
  has_many :authentication_records

  before_validation :set_secret, :set_csrf_token, :set_impersonator,
                    :normalize_user_agent
  before_create :set_initial_accessed_at, :set_initial_sudo_enabled_at
  after_create_commit :instrument_create, :instrument_access
  after_commit :instrument_location_change, on: :update, if: :saved_change_to_ip?
  after_commit :instrument_revoke, on: :update, if: :saved_change_to_revoked_at?
  after_save :set_user_time_zone, if: :saved_change_to_time_zone_name?
  before_destroy :ensure_revoked_on_destroy

  validates_presence_of :user_id
  validate :user_present, :user_is_human
  validate :impersonator_and_session_match, :impersonator_is_staff,
           :impersonator_has_sudo, :impersonator_is_not_user

  validates_presence_of :hashed_key
  validates_format_of :hashed_key, with: HASHED_KEY_RE
  validates_format_of :hashed_private_mode_key, with: HASHED_KEY_RE, allow_nil: true
  validates_format_of :secret, with: SECRET_RE
  validates_format_of :csrf_token, with: CSRF_TOKEN_RE
  validates_inclusion_of :revoked_reason, in: VALID_REVOKE_REASONS, allow_nil: true

  default_scope -> { order("accessed_at DESC") }

  # Public: Find all expired sessions.
  #
  # All these sessions are for sure inactive and can safely be pruned from the
  # database to BSS.
  #
  # Returns collection of expired records.
  scope :expired, -> { where("accessed_at < ? OR expires_at <= ?", user_session_expiration.ago, Time.now.utc) }

  # Public: Find all non-expired sessions.
  #
  # All these sessions are valid based on the expiration time period.
  #
  # Returns collection of non-expired records.
  scope :unexpired, -> { where("accessed_at > ? AND (expires_at IS NULL OR expires_at > ?)", user_session_expiration.ago, Time.now.utc) }

  scope :unrevoked, -> { where(revoked_at: nil) }

  scope :not_impersonated, -> { where(arel_table[:impersonator_session_id].eq(nil)) }

  scope :user_facing, -> { unexpired.unrevoked.not_impersonated }

  scope :recent, -> { where("accessed_at > ?", RECENTNESS.ago) }

  # These will all be stored as binary in the future to avoid
  # case sensitivity bugs.
  extend GitHub::Encoding
  force_utf8_encoding :hashed_key, :hashed_gist_key, :hashed_private_mode_key, :csrf_token, :secret

  # Public: Generate a new random key for the client.
  #
  # Returns a base64 String.
  def self.random_key
    SecureRandom.urlsafe_base64(KEY_SIZE)
  end

  # Public: Hash client key for server side persistence.
  #
  # key - A String
  #
  # Returns hashed base64 String.
  def self.hash_key(key)
    HASHED_KEY_DIGEST.base64digest(key)
  end

  # Public: Generates new random hashed key.
  #
  # Exists mainly for debugging and tests.
  #
  # Returns random hashed base64 String.
  def self.random_hashed_key
    hash_key(random_key)
  end

  # Public: Generates a new random key pair, unhashed and hashed.
  #
  # Returns base64 String and base64 hashed version of the first String.
  def self.random_key_pair
    key = random_key
    [key, hash_key(key)]
  end

  # Public: Generates a new random key pair, unhashed and hashed.
  #         Unhashed key will have business shortcode as suffix
  #
  # Returns base64 String with business shortcode as suffix and base64 hashed version of the first String.
  def self.random_key_pair_with_business(business)
    key = "#{random_key}_#{business.shortcode}"
    [key, hash_key(key)]
  end

  # Internal: Whether the provided key has a valid format.
  #
  # key   - Base64 String key.
  #
  # Returns a boolean.
  def self.valid_key_format?(key)
    key && key.valid_encoding? && (key.match(BASE64_KEY_WITH_SHORTCODE_RE) || key.match(BASE64_KEY_RE))
  end

  # Internal: Authenticate user via signed key.
  #
  # key   - Base64 String key.
  # block - Proc accepting a hashed key to lookup session
  #
  # Returns an active [UserSession, String] or nil.
  def self.authenticate_key(key)
    # Ensure key was unpacked as expected.
    return unless valid_key_format?(key)

    # Lookup session from key.
    return unless session = yield(hash_key(key))

    # Validate session.
    return unless session.active?

    [session, key]
  end

  # Public: Authenticate user via unique key.
  #
  # Ensures the returned session is always active and valid. So always use
  # this method over `find_by_hashed_key` for authentication.
  #
  # key - Base64 String key ID
  # hashed_key_column - The respective hashed key column for the provided key (optional).
  #
  # Returns an active [UserSession, String] or nil.
  def self.authenticate(key, hashed_key_column: :hashed_key)
    authenticate_key(key) do |hashed_key|
      unscoped do
        where(hashed_key_column => hashed_key).first
      end
    end
  end

  # Public: Authenticate user to access Private mode via a signed key.
  #
  # key - Base64 String key ID
  #
  # Returns an active [UserSession, String] or nil.
  def self.authenticate_private_mode(key)
    authenticate_key(key) do |hashed_key|
      unscoped do
        find_by(hashed_private_mode_key: hashed_key)
      end
    end
  end

  # Public: Find all potentially affected sessions due to a security incident.
  #
  # Excludes sessions that are already revoked.
  #
  # incident_resolved_at - Time security incident was resolved. Use a constant
  #                        like UserSession::HEARTBLEED_INCIDENT.
  #
  # Returns a scope of records.
  def self.potentially_compromised(incident_resolved_at)
    where([
      "accessed_at > ? AND revoked_at IS NULL AND created_at < ?",
      user_session_expiration.ago, incident_resolved_at
    ])
  end

  # Public: Revoke potentially affected sessions due to a security incident.
  #
  # incident_resolved_at - Time security incident was resolved. Use a constant
  #                        like UserSession::HEARTBLEED_INCIDENT.
  #
  # inactivity_duration - Duration of recent activity to exclude from
  #                       revocation. May also be set to nil to ignore
  #                       inactivity and revoke all affected sessions.
  #                       (default: 1 hour)
  #
  # Returns Integer of updated sessions.
  def self.revoke_potentially_compromised(incident_resolved_at, inactivity_duration = 1.hour)
    scope = potentially_compromised(incident_resolved_at)
    scope = scope.where(["accessed_at < ?", inactivity_duration.ago]) if inactivity_duration
    scope.revoke_all(:security_incident)
  end

  # Public: Creates a new user_session key + hashed_key based on if the user is an EMU.
  #
  # user - The user
  #
  # Returns base64 String and base64 hashed version of the first String.
  def self.create_user_session_key_pair(user)
    key, hashed_key = if user.is_enterprise_managed? &&
      (GitHub.flipper[:user_session_with_emu_suffix].enabled?(user) ||
      GitHub.flipper[:user_session_with_emu_suffix].enabled?(user.enterprise_managed_business))
      UserSession.random_key_pair_with_business(user.enterprise_managed_business)
    else
      UserSession.random_key_pair
    end
  end

  # Public: HMAC signing instance for session's own secret.
  #
  # Returns new OpenSSL::HMAC instance.
  def secret_hmac
    OpenSSL::HMAC.new(self.secret, SECRET_HMAC_DIGEST.new)
  end

  # Public: Is session active and good to authenticate against.
  #
  # Returns true or false.
  def active?
    self.state == :active
  end

  # Public: Get session expires duration.
  #
  # How long after their last access should sessions expire in seconds.
  #
  # Returns Duration.
  def self.user_session_expiration
    GitHub.user_session_timeout.seconds
  end
  delegate :user_session_expiration, to: "self.class"

  # Public: Get session access log write throttle
  #
  # Window of time between access log writes
  #
  # Defaults to 1.day. Needs to be adjusted if user_session_expiration is set to
  # less than a day.
  #
  # Returns Duration
  def self.access_throttling
    GitHub.user_session_access_throttling.seconds
  end
  delegate :access_throttling, to: "self.class"

  # Public: Get session expires duration.
  #
  # Returns 2 weeks for regular sessions and just an hour for
  # impersonated ones.
  #
  # Returns Duration.
  def expires
    if impersonated?
      IMPERSONATED_EXPIRES
    else
      user_session_expiration
    end
  end

  # Expiry time for this session. Always works in UTC to prevent
  # timezone issues
  def expire_time
    expirations = [accessed_at + expires]
    if user&.feature_enabled?(:emu_user_session_expiration) && expires_at
      expirations << expires_at
    end
    expirations.min
  end

  # Public: Is session expired?
  #
  # Returns true or false.
  def expired?
    return true if accessed_at < expires.ago

    return false unless user&.feature_enabled?(:emu_user_session_expiration)
    return false unless expires_at
    T.must(expires_at) <= Time.now.utc
  end

  # Public: Determine if session has be manually revoked.
  #
  # If the session is impersonated, also check the parent session to see
  # if it was also revoked.
  #
  # Returns true or false.
  def revoked?
    revoked_at.present? ||
      (impersonated? && impersonator_session&.revoked?)
  end

  # Public: Determine if a session is anomalous. Omits unrecognized_devices
  # until we ship those alerts.
  #
  # Returns true if the session is anomalous and is from an
  # unrecognized_device_and_location or unrecognized_location; otherwise false.
  def anomalous?
    !!sign_in_record&.anomalous?
  end

  # Public: The previous user session that hasn't expired and controlled by an
  # impersonator.
  #
  # Returns UserSession instance.
  def previous_user_session
    return @previous_user_session if defined?(@previous_user_session)
    @previous_user_session = user&.sessions&.unexpired&.where([
      "user_sessions.impersonator_session_id IS NULL AND user_sessions.revoked_at IS NULL AND user_sessions.id <> ?",
      id,
    ])&.first
  end

  # Public: Revoke session so it can no longer be used for authentication.
  #
  # reason - String or Symbol identifier for why the session is being revoked.
  #
  # Returns self.
  def revoke(reason, unverify_device: true)
    reason = reason.to_s
    if !VALID_REVOKE_REASONS.include?(reason)
      raise ArgumentError, "invalid revocation reason: #{reason}"
    end

    unless revoked?
      if unverify_device && %w(logout unimpersonate).exclude?(reason) && !impersonated?
        self.sign_in_record&.authenticated_device&.unverify(reason: reason) if GitHub.sign_in_analysis_enabled?
      end
      self.revoked_at = Time.current
      self.revoked_reason = reason.to_s
      save
    end
    self
  end

  private def ensure_revoked_on_destroy
    revoke(:account_destroy) if active?

    GitHub.dogstats.increment("user_session.destroy", tags: [
      "state:#{state}",
      "revoked:#{revoked?}",
      "expired:#{expired?}",
    ])
  end

  # Public: Mass revoke sessions.
  #
  # Updates all sessions that aren't expired or already revoked.
  #
  # reason - String or Symbol identifier for why the session is being revoked.
  #
  # Returns Integer count of updated rows.
  def self.revoke_all(reason)
    if !VALID_REVOKE_REASONS.include?(reason.to_s)
      raise ArgumentError, "invalid revocation reason: #{reason}"
    end

    # Generates the following SQL.
    #
    # UPDATE `user_sessions`
    #   SET `revoked_at` = '2014-04-08 12:00:00',
    #       `revoked_reason` = 'security_incident'
    #   WHERE ((`user_sessions`.`revoked_at` IS NULL) AND
    #          (accessed_at > '2014-03-25 12:00:00'))
    #
    where(["accessed_at > ?", user_session_expiration.ago]).where(revoked_at: nil)
      .update_all({ revoked_at: Time.current, revoked_reason: reason.to_s })
  end

  # Public: Creates a new user_session key + hashed_key based on if the user is an EMU.
  #
  # Rotates the current hashed_key value and returns the new values.
  #
  # Returns base64 String and base64 hashed version of the first String.
  def rotate_hashed_key(reason)
    key, hashed_key = UserSession.create_user_session_key_pair(self.user)
    update_column :hashed_key, hashed_key
    instrument_rotate(reason)

    [key, hashed_key]
  end

  # Public: Returns sessions with a valid web sign in record
  #
  # Retrieves the web sign in record. There should only ever
  # be one web sign in record per session.
  #
  # Returns the matching web sign in record for the session
  def sign_in_record
    return @sign_in_record if defined?(@sign_in_record)
    @sign_in_record = authentication_records.web_sign_ins.first
  end

  # Public: Get session state identifier.
  #
  # Returns Symbol state.
  #   :active  - Active and good for authentication.
  #   :expired - Hasn't been accessed in 2 weeks, no longer good.
  #   :revoked - Manually revoked by user or the system before it had expired.
  #   :invalid - Bad record validation state. Any session in this state
  #              is a symtom of a bug.
  def state
    if expired?
      :expired
    elsif revoked?
      :revoked
    elsif !valid?
      :invalid
    else
      :active
    end
  end

  # Public: Check if session is a staff impersonation of a user.
  #
  # Returns true or false.
  def impersonated?
    impersonator_session_id.present?
  end

  # Public: Check if session has sudo capabilities.
  #
  # Always returns true unless our authentication method supports password
  # verification.
  #
  # Impersonated staff sessions are always in sudo.
  #
  # Returns true or false.
  def sudo?
    if !GitHub.auth.sudo_mode_enabled?(user)
      true
    elsif impersonated?
      true
    elsif sudo_enabled_at
      T.must(sudo_enabled_at) > SUDO_EXPIRY.ago
    else
      false
    end
  end

  # Public: Touch sudo timestamp and enable sudo for another 2 hours.
  #
  # Returns nothing.
  def enable_sudo(credential_type)
    if sudo_enabled_at.nil? || T.must(sudo_enabled_at) < SUDO_THROTTLING.ago
      ActiveRecord::Base.connected_to(role: :writing) do
        update_column :sudo_enabled_at, Time.current
      end

      instrument :sudo, {
        actor: self.user,
        actor_ip: self.ip,
        device_id: @device_id,
        credential_type: credential_type
      }
    end
  end

  # Public: Clear sudo timestamp and kill sudo mode.
  #
  # Exists mainly for debugging and tests.
  #
  # Returns nothing.
  def expire_sudo
    ActiveRecord::Base.connected_to(role: :writing) do
      update_column(:sudo_enabled_at, nil)
    end
  end

  # Public: Check is session was accessed within the last hour.
  #
  # Returns true or false.
  def recent?
    accessed_at > RECENTNESS.ago
  end

  # Public: Set in_use to true.
  #
  # The Account Switcher relies on this column for peripheral services in the platform
  # (i.e. Gists, Pages) to keep their sessions in sync with Dotcom.
  #
  # Returns true if a write was performed, false otherwise.
  def mark_in_use
    return false if GitHub.cache.get(update_cache_key("in_use"))

    ActiveRecord::Base.connected_to(role: :writing) do
      update_column :in_use, true
    end

    GitHub.cache.set(update_cache_key("in_use"), true, IN_USE_THROTTLING.to_i)
    true
  end

  # Public: Touch accessed timestamp to note user accessed the session.
  #
  # Writes are throttled to avoid writes on every page load. If the IP
  # has not changed, writes are throttled to once in a 24 hour period.
  # If the IP address has changed, writes are throttled to once in a 5
  # minute period.
  #
  # request - ActionDispatch::Request to log in request/cookie metadata.
  #
  # returns the result of the update operation (if any)
  def access(request)
    return if new_record?
    assign_attributes_from_request(request)

    # ensure the session is marked as in use if it's not already.  this is important signal used by peripheral services,
    # like Gists and Pages, to keep their sessions in sync with Dotcom.
    if !in_use?
      tags = ["in_use:#{in_use}"]
      updated = mark_in_use
      GitHub.dogstats.increment("account_switcher.user_session_in_use_on_access", tags: tags.concat(["throttled:#{!updated}"]))
    end

    if update_session_data?
      access_risk_metric(request&.params)
      GitHub.dogstats.increment("user_session", tags: ["action:access"])
      update_attributes_and_accessed_at
    end
  end

  # Private: Do the actual access work of updating accessed_at and optionally
  # updating metadata from the request
  #
  # returns the result of the update operation
  def update_attributes_and_accessed_at
    pending_changes = changed.any?
    if ip_changed?
      GitHub.cache.set(update_cache_key("ip"), true, IP_CHANGE_THROTTLING.to_i)
    end

    saved = ActiveRecord::Base.connected_to(role: :writing) do
      if pending_changes
        self.accessed_at = Time.current
        save
      else
        update_column :accessed_at, Time.current
      end
    end

    GitHub.cache.set(update_cache_key("accessed_at"), true, access_throttling.to_i)

    if run_session_analysis?(saved, pending_changes)
      analysis = AppSecurity::SessionAnalysis.new(self, saved_changes.keys)
      instrument_risk_assessment(analysis.data, analysis.should_revoke?) if analysis.should_instrument?
      RevokeCompromisedSessionJob.enqueue(self.user_id, self.id) if analysis.should_revoke?

      if feature_enabled_for_user?(:session_theft_stats)
        # Determine if subsequent requests indicate impossible travel
        time_since_last_update_in_seconds = self.updated_at - self.updated_at_before_last_save
        distance_km = AppSecurity::SessionAnalysis.distance_between_locations(location, last_location)

        if AppSecurity::SessionAnalysis.naive_impossible_travel?(distance_km, time_since_last_update_in_seconds)
          same_country = self.last_location[:country_code] == self.location[:country_code]
          GitHub.dogstats.increment("session_theft.risk_signal", tags: ["reason:impossible_travel", "country:#{self.location[:country_code]}", "country_prev:#{self.last_location[:country_code]}", "same_country:#{same_country}", "user_agent_change:#{user_agent_changed?}"])

          GitHub.logger.info(
            "code.function" => "user_session.access.impossible_travel",
            "gh.auth.user_id" => self.user_id,
            "gh.auth.session.id" => self.id,
            "gh.auth.ip" => self.ip,
            "gh.auth.ip_was" => self.ip_before_last_save,
            "gh.auth.location" => self.location,
            "gh.auth.location_was" => self.last_location,
            "gh.auth.user_agent" => self.user_agent,
            "gh.auth.user_agent_was" => self.user_agent_before_last_save,
            "gh.auth.updated_at" => self.updated_at,
            "gh.auth.updated_at_was" => self.updated_at_before_last_save,
            "gh.auth.time_since_last_update_in_seconds" => time_since_last_update_in_seconds,
            "gh.auth.distance_km" => distance_km,
          )
        end
      end
    end

    instrument_access
    saved
  end
  private :update_attributes_and_accessed_at

  def run_session_analysis?(saved, pending_changes)
    return false unless GitHub.sign_in_analysis_enabled?
    return false if GitHub.flipper[:session_analysis_opt_out].enabled?(self)
    # more than just accessed_at needs to have been updated
    saved && pending_changes && !impersonated?
  end

  def access_risk_metric(params)
    controller_action = "%s#%s" % [params[:controller], params[:action]]
    if controller_action == "files#disambiguate" || controller_action == "settings/email_preferences#show"
      GitHub.dogstats.increment("session_theft.risk_signal", tags: ["reason:#{controller_action}", "ip_change:#{ip_changed?}", "user_agent_change:#{user_agent_changed?}"])
    end
  end

  def assign_attributes_from_request(request)
    self.ip = request.remote_ip
    self.user_agent = request.user_agent
    if zone = ActiveSupport::TimeZone[request.cookies["tz"].to_s]
      self.time_zone_name = zone.name
    end

    @device_id = request.cookies["_device_id"] if AuthenticatedDevice::DEVICE_ID_REGEX.match?(request.cookies["_device_id"])
    @client_id = Analytics::Visitor.with_octolytics_id(request.cookies["_octo"])&.unversioned_octolytics_id
    @request_id = request.env["HTTP_X_GITHUB_REQUEST_ID"]
  end

  # Public: Get the location of the session's IP.
  #
  # Returns a Hash containing as much location information as was available.
  def location
    return @location if defined? @location
    @location = GitHub::Location.look_up(self.ip)
    GitHub.audit.normalize_location(@location)
    @location
  end

  # Public: Get the location of the session's last IP.
  #
  # Returns a Hash containing as much location information as was available.
  def last_location
    return @last_location if defined? @last_location
    @last_location = GitHub::Location.look_up(self.ip_before_last_save)
    GitHub.audit.normalize_location(@last_location)
    @last_location
  end

  # Public: Parse user agent string.
  #
  # Returns UserAgent instance or nil.
  def ua
    return @ua if defined? @ua
    @ua = user_agent ? Browser.new(user_agent) : nil
  end

  # Public: Check if session is a mobile device.
  #
  # Returns a boolean.
  def mobile?
    ua && ua.device.mobile?
  end

  # Public: True if the user's session contains geo-location information,
  # and the country code for that location matches the arugment.
  def from_country?(country_code)
    detailed_location = location
    !detailed_location.nil? && detailed_location[:country_code] == country_code
  end

  def event_context(prefix: :session)
    {
      "#{prefix}_id".to_sym => id,
    }
  end

  # Public: True if value matches a valid session for oauth_application access
  def valid_for_oauth_application?(oauth_application, value)
    oauth_application_key_hmac = secret_hmac.update(oauth_application.key).hexdigest
    SecurityUtils.secure_compare(value, oauth_application_key_hmac)
  end

  # Checks the sign in history to determine if this session is associated
  # with an unrecognized sign in event
  def associated_with_unrecognized_sign_in?
    !!self.authentication_records.web_sign_ins.first&.flagged_reason
  end

  def log_hash
    {
      "gh.auth.login" => self.user&.login,
      "gh.enduser.id" => self.user_id,
      "gh.auth.ip" => self.ip,
      "gh.auth.ip_was" => self.ip_before_last_save,
      "gh.auth.location" => self.location,
      "gh.auth.location_was" => self.last_location,
      "gh.auth.associated_user.ids" => self.users,
      "gh.auth.associated_user.logins" => self.user_logins,
      "gh.auth.session.id" => self.id,
      "user_agent.original_was" => self.user_agent_before_last_save,
      "user_agent.original" => self.user_agent,
      "gh.auth.session.updated_at_was" => self.updated_at_before_last_save,
      "gh.auth.session.updated_at" => self.updated_at,
    }
  end

  private

  # Internal: Populate secret signing token.
  def set_secret
    self.secret ||= SecureRandom.base64(SECRET_BYTES)
  end

  # Internal: Populate CSRF token.
  def set_csrf_token
    self.csrf_token ||= SecureRandom.base64(CSRF_BYTES)
  end

  # Internal: Initialize the accesed at timestamp.
  def set_initial_accessed_at
    self.accessed_at = Time.current if self.accessed_at.nil?
  end

  # Internal: Initialize sudo mode on create.
  def set_initial_sudo_enabled_at
    self.sudo_enabled_at = Time.current if self.sudo_enabled_at.nil?
  end

  # Internal: Set denormalized impersonator user association from the
  # impersonator session.
  #
  # This is mainly kept for historical purposes. Since sessions are
  # ephemeral, its handy to be able to get the original impersonating
  # user long after the session is pruned from the database.
  #
  # Set the value if its not already. Validation steps will ensure
  # consistency.
  def set_impersonator
    if impersonator_session
      self.impersonator ||= T.must(impersonator_session).user
    end
  end

  # Internal: Ensure theres a user associated with the session.
  #
  # UserSessions can not be created for anonymous purposes.
  def user_present
    if user.nil?
      errors.add :user_id, "is not a valid user"
    end
  end

  # Internal: Ensure user is not a User subclass.
  #
  # Organizations and bots can never log in. This also covers the case of
  # transforming a user into an organization. At that time, all user
  # sessions should be revoked, so just in case.
  def user_is_human
    if user && !T.must(user).user?
      errors.add :user_id, "is not a human user"
    end
  end

  # Internal: Consistency check the denormalized `impersonator_id` and
  # `impersonator_session_id` fields. The impersonator user must always
  # match the owner of the impersonator session.
  def impersonator_and_session_match
    if impersonator || impersonator_session
      if !impersonator_session
        errors.add :impersonator_session_id, "must be set"
      elsif impersonator != T.must(impersonator_session).user
        errors.add :impersonator_id, "doesn't match impersonator session"
      end
    end
  end

  # Internal: Ensure impersonator is staff.
  #
  # Only staff can impersonate other users. If for some reason a user
  # is demoted from staff, all their impersonated sessions would then be
  # invalid.
  def impersonator_is_staff
    if impersonator && !T.must(impersonator).site_admin?
      errors.add :impersonator_id, "is not staff"
    end
  end

  # Internal: Ensure impersonator session has sudo.
  def impersonator_has_sudo
    if impersonator_session && !T.must(impersonator_session).sudo?
      errors.add :impersonator_session_id, "must have sudo"
    end
  end

  # Internal: Ensure users can not create impersonated sessions for their
  # own account. Just why, really?
  def impersonator_is_not_user
    if impersonator && impersonator == user
      errors.add :impersonator_id, "can not pose as self"
    end
  end

  # Internal: Update associated user's time zone when it changes on the
  # session.
  def set_user_time_zone
    T.must(user).time_zone_name = self.time_zone_name

    ActiveRecord::Base.connected_to(role: :writing) do
      T.must(user).save
    end
  end

  # Internal: Normalize and clean user agent value before saving it. Since
  # we pull these directly from request headers they may have some garbage.
  def normalize_user_agent
    self.user_agent = clean_string_column_value(self.user_agent) if self.user_agent
  end

  # Internal: find previous device_id via authentication records
  def device_id_was
    return @device_id_was if defined? @device_id_was
    @device_id_was = self.authentication_records.first&.authenticated_device&.device_id
  end

  # Internal: find any associated users
  def users
    return @users if defined? @users
    @users = []
    @users = AuthenticatedDevice.where(device_id: @device_id).pluck(:user_id) if @device_id
  end

  # Internal: find any associated user logins
  def user_logins
    return @user_logins if defined? @user_logins
    @user_logins = []
    @user_logins = User.where(id: users).order(:id).pluck(:login) if self.users.any?
  end

  # Internal: Clean string to be inserted into a MySQL TEXT(255) column.
  #
  # Scrubs anyone non-ASCII characters and truncates to 255 characters.
  #
  # str - String to clean
  #
  # Returns a cleaned String.
  def clean_string_column_value(str)
    str.dup.force_encoding("US-ASCII").scrub[0, 255]
  end

  def event_payload
    {
      event_prefix => self,
      :user        => user,
    }
  end

  def change_event_payload
    {
      actor: self.user,
      actor_ip: self.ip,
      actor_ip_was: self.ip_before_last_save,
      actor_location_was: self.last_location,
      actor_location: self.location,
      actor_timezone: self.time_zone_name,
      actor_timezone_was: self.time_zone_name_before_last_save,
      device_id_was: device_id_was,
      accessed_at_was: self.accessed_at_before_last_save,
      user_agent_was: self.user_agent_before_last_save,
      associated_user_ids: self.users,
      associated_user_logins:  self.user_logins,
    }
  end

  # Internal: Triggers a "user_session.create" event for logging purposes.
  #
  # Occurs only once when a valid session is created.
  def instrument_create
    instrument :create
  end

  # Internal: Triggers a "user_session.access" event for logging purposes.
  #
  # Occurs any time a makes a request with the associated user session.
  # Note that is call is rated limited a 5 minute window.
  def instrument_access
    instrument :access
  end

  # Internal: Triggers a "user_session.revoke" event for audit logging
  def instrument_revoke
    instrument :revoke, { reason: self.revoked_reason }
  end

  # Internal: Triggers a "user_session.rotate" event for audit logging
  def instrument_rotate(reason)
    instrument :rotate, { reason: reason }
  end

  # Internal: Triggers a "user_session.risk_assessment" event for audit logging
  # Also emits user_session_update hydro risk event for platform-health use
  def instrument_risk_assessment(data, revoke)
    payload = change_event_payload.merge(data)
    instrument :risk_assessment, payload
    GlobalInstrumenter.instrument("user.user_session_update", payload.merge({ updated_at: self.updated_at, device_id: @device_id, revoke: revoke }))
  end

  # Internal: Triggers "user_session.country_change" and "user.session_ip_change" event for logging purposes
  def instrument_location_change
    # need to force update the memoized location variables otherwise they don't get updated on ip change
    remove_instance_variable(:@location) if defined? @location
    remove_instance_variable(:@last_location) if defined? @last_location

    # We want the audit entry to only be for legitimate actors which may
    # have (un)intentionally changed countries. Bots become too spammy
    return if impersonated?
    return if AuthenticationRecord.user_rate_limited?(self.user)

    same_country = self.last_location[:country_code] == self.location[:country_code]

    GitHub.logger.info(log_hash.merge({
        "code.function" => "user_session.location_change",
        "gh.auth.device.id" => @device_id,
        "gh.auth.device.id_was" => device_id_was,
        "http.client_id" => @client_id,
        "gh.request_id" => @request_id,
      })
    )

    change_data = {
      actor: self.user,
      previous_ip: self.ip_before_last_save,
      current_ip: self.ip,
      previous_location: self.last_location,
      current_location: self.location,
      actor_timezone: self.time_zone_name,
      actor_timezone_was: self.time_zone_name_before_last_save,
      user_ids_for_device: self.users,
      user_logins_for_device: self.user_logins,
      previous_device_id: device_id_was,
      updated_at: self.updated_at,
    }

    GlobalInstrumenter.instrument("user.last_ip_update", change_data)

    if user&.authenticated_devices&.find_by(device_id: @device_id).nil?
      GitHub.dogstats.increment("user_session.invalid_device", tags: [
          "device_id_present:#{!@device_id.nil?}",
          "device_id_was_present:#{!device_id_was.nil?}",
          "associated_users_present:#{self.users.any?}",
          "associated_devices_high_count:#{self.users.count > 1}",
          "country_changed:#{!same_country}"
        ])
    end

    # We only care if the country has changed
    return if same_country

    instrument :country_change, change_event_payload

    GlobalInstrumenter.instrument("user.user_country_change",
      actor: self.user,
      previous_location: self.last_location,
      anomalous_session: anomalous?,
    )
  end

  def update_session_data?
    accessed_at_needs_updating? || ip_needs_updating?
  end

  # Check whether this user_session record's accessed_at attribute has been
  # updated or that we've already recently checked for access. We fallback to
  # checking the cache in case there's database replication lag on recently
  # updated sessions.
  def accessed_at_needs_updating?
    self.accessed_at < access_throttling.ago &&
      !GitHub.cache.get(update_cache_key("accessed_at"))
  end

  # Check whether this user_session record's ip attribute has been
  # updated or that we've already recently checked for access. We fallback to
  # checking the cache in case there's database replication lag on recently
  # updated sessions.
  def ip_needs_updating?
    ip_changed? &&
      self.updated_at && T.must(self.updated_at) <= IP_CHANGE_THROTTLING.ago &&
      !GitHub.cache.get(update_cache_key("ip"))
  end

  def update_cache_key(column)
    "v2:user_session:#{id}:update_#{column}"
  end

  def feature_enabled_for_user?(feature_name)
    user&.feature_enabled?(feature_name, memoize: false)
  end
end
