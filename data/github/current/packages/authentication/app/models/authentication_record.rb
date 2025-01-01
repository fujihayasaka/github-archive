# typed: true
# frozen_string_literal: true

class AuthenticationRecord < ApplicationRecord::Ballast
  extend GitHub::RateLimitable
  include GitHub::RateLimitable
  include GitHub::Relay::GlobalIdentification

  NOTIFICATION_LIMIT = Rails.env.production? ? 5 : 1
  NOTIFICATION_RATE_LIMIT_TTL = 24.hours
  RATE_LIMIT_OPTIONS = {
    max_tries: NOTIFICATION_LIMIT,
    ttl: NOTIFICATION_RATE_LIMIT_TTL,
  }

  # The amount of time we give someone to complete a 2FA challenge before
  # notifying them of a potential unexpected sign in
  TWO_FACTOR_LENIENCY = 10.minutes

  LOW_NOISE_REPORTS = %i(unrecognized_location unrecognized_device_and_location no_records_exist)

  UNEXPECTED_SIGN_IN_REASONS = %w{
    unrecognized_location
    unrecognized_device
    unrecognized_device_and_location
    no_records_exist
  }

  belongs_to :user
  belongs_to :user_session
  belongs_to :authenticated_device

  before_validation :normalize_user_agent
  before_create :track_device_and_origin
  after_commit :queue_partial_authentication_followup, on: :create
  after_create :associate_partial_sign_in!
  after_commit :deliver_unexpected_sign_in_notification, on: :create, if: :flagged_reason

  # We want to explicitly include the password_changed client here because it also
  # acts as the first record of a new user session
  scope :web_sign_ins, -> { where(client: [:web, :password_changed]) }
  scope :two_factor_partial_sign_ins, -> { where(client: :two_factor_partial_sign_in) }
  scope :authenticated_events, -> { where.not(client: [:two_factor_partial_sign_in]) }

  # Time-based scopes
  scope :recent, -> (since) { where(AuthenticationRecord.arel_table[:created_at].gteq(since)) }
  scope :subsequent_to, -> (this) { where(user: this.user).where(AuthenticationRecord.arel_table[:created_at].gteq(this.created_at)) }
  scope :prior_to, -> (this) { where(user: this.user).where(AuthenticationRecord.arel_table[:created_at].lteq(this.created_at)) }

  # Similarity lookups
  scope :same_device_as, -> (this) { where(user: this.user, authenticated_device_id: this.authenticated_device_id) }
  scope :same_session_as, -> (this) { where(user: this.user, user_session_id: this.user_session_id).where.not(user_session_id: nil) }
  scope :same_location_as, -> (this) { where(user: this.user, country_code: this.country_code) }
  scope :unassociated_partial_sign_ins, -> { where(user_session_id: nil) }

  validates :octolytics_id, presence: true
  validates :ip_address, presence: true
  validates :flagged_reason, inclusion: { in: UNEXPECTED_SIGN_IN_REASONS, allow_blank: true }
  validates :client, inclusion: {
    in: %w(
      two_factor_partial_sign_in
      password_changed
      sign_up
      user_session
      web
    ),
  }

  MAX_REGION_NAME_LENGTH = 64 # Length of the region_name field in the database
  before_save :truncate_region_name

  # Normal human users shouldn't be generating this many unexpected alerts
  # This limit determines the number of authentication records we will perform
  # actions (notifications, audit logging, etc..) on within a 24 hour period
  # once this limit is reached we consider the user to be a bot
  def self.user_rate_limited?(user)
    rate_limit_check("unexpected-login:#{user.id}", RATE_LIMIT_OPTIONS).at_limit?
  end

  def location
    @location ||= GitHub::Location.look_up(self.ip_address)
  end

  def location=(location)
    @location = location
    self.city = @location[:city]
    self.region_name = @location[:region_name]
    self.country_code = @location[:country_code]
  end

  # Truncate region name if longer than 64 characters
  def truncate_region_name
    return unless @location
    return unless @location[:region_name].present?
    return if @location[:region_name].length <= MAX_REGION_NAME_LENGTH

    self.region_name = "#{@location[:region_name][0...MAX_REGION_NAME_LENGTH]}"
  end

  # "web" represents a standard login flow
  def web_sign_in?
    self.client.to_s == "web"
  end

  # "two factor failure" is consistent with Authentication::Result and indicates
  # a correct password was provided but 2FA is required
  def two_factor_partial_sign_in?
    self.client.to_s == "two_factor_partial_sign_in"
  end

  # A record created by an update to an existing user_session. We consider
  # updates to a user session to be the same as an authenticated event.
  def user_session_update?
    self.client.to_s == "user_session"
  end

  def deliver_sign_in_notification?
    # Events on employee unicorns are excluded to reduce noise.
    return false if GitHub.employee_unicorn?

    # Unrecognized device alerts are currently disabled.
    return false if LOW_NOISE_REPORTS.exclude?(self.flagged_reason&.to_sym)

    # SCIM users logging in for the first time are excluded to reduce noise.
    return false if T.must(self.user).scim_managed_user? && self.flagged_reason.to_s == "no_records_exist"

    T.must(self.user).sign_in_analysis_enabled? && # We only deliver notification on dotcom currently
      !AuthenticationRecord.user_rate_limited?(self.user) # has not been rate limited
  end

  def anomalous?
    !!flagged_reason && flagged_reason.to_s != "unrecognized_device"
  end

  def associated_session_revoked?
    self.user_session.nil? || !!T.must(self.user_session).revoked_at
  end

  def known_device?
    if new_record?
      raise "known_device? cannot be checked unless the record is persisted because it may not be correct"
    end
    self.flagged_reason.nil? || self.flagged_reason.to_s == "unrecognized_location"
  end

  def known_location?
    if new_record?
      raise "known_location? cannot be checked unless the record is persisted because it may not be correct"
    end
    self.flagged_reason.nil? || self.flagged_reason.to_s == "unrecognized_device"
  end

  # Finds the partial sign in event for completed 2fa flows.
  def associated_partial_sign_in
    return @associated_partial_sign_in if defined?(@associated_partial_sign_in)
    unless web_sign_in?
      raise RuntimeError, "Cannot find partial sign in event for non-web sign ins"
    end

    ActiveRecord::Base.connected_to(role: :reading) do
      @associated_partial_sign_in = T.must(self.user).
        authentication_records.
        two_factor_partial_sign_ins.
        same_device_as(self).
        prior_to(self).
        unassociated_partial_sign_ins.
        # user could have multiple partial attempts on the same device, take the latest
        order(created_at: :desc).
        limit(1).
        first
    end
  end

  private

  def associate_partial_sign_in!
    return unless T.must(self.user).sign_in_analysis_enabled?

    if web_sign_in? && T.must(self.user).two_factor_authentication_enabled?
      if associated_partial_sign_in.nil?
        GitHub.dogstats.increment("authentication_records", tags: ["error:failed_to_associate_partial_sign_in", "action:associate"])
      else
        associated_partial_sign_in.update!(user_session_id: self.user_session_id)
      end
    end
  end

  def track_device_and_origin
    # Only analyze sign-in / partial 2FA events
    return if !two_factor_partial_sign_in? && !web_sign_in?
    # Uninteresting events are not analyzed
    return unless !!unexpected_sign_in_reason

    self.flagged_reason = unexpected_sign_in_reason

    # we want to instrument all unexpected logins except for when a user has no records that exists
    T.must(user).instrument_unexpected_login(self) if self.flagged_reason.to_s != "no_records_exist"
    stat_unexpected_sign_in

    # We don't want to increment on a 2FA event because they use a different mailer
    # which isn't limited by this rate limiter
    return if two_factor_partial_sign_in?
    rate_limit_increment("unexpected-login:#{T.must(user).id}", { ttl: NOTIFICATION_RATE_LIMIT_TTL })
  end

  # Determines why we will notify the user of the unexpected sign in.
  def unexpected_sign_in_reason
    return @unexpected_sign_in_reason if defined?(@unexpected_sign_in_reason)

    ActiveRecord::Base.connected_to(role: :reading) do
      unrecognized_device = !T.must(self.user).authentication_records
        .authenticated_events
        .same_device_as(self)
        .exists?

      unrecognized_location = !T.must(self.user).authentication_records
        .authenticated_events
        .same_location_as(self)
        .exists?

      no_records_exist = T.must(self.user).authentication_records.empty?

      @unexpected_sign_in_reason = if no_records_exist && !two_factor_partial_sign_in?
        # we do not want to flag no_records_exist for 2FA partial sign ins
        :no_records_exist
      elsif unrecognized_location && unrecognized_device
        :unrecognized_device_and_location
      elsif unrecognized_location
        :unrecognized_location
      elsif unrecognized_device
        :unrecognized_device
      else
        # this is a recognized device or location
        nil
      end
    end
  end

  def stat_unexpected_sign_in
    tags = [
      "from:#{self.client}",
      "country_code:#{self.country_code}",
      "reason:#{unexpected_sign_in_reason.to_s.dasherize}",
      "rate_limited:#{AuthenticationRecord.user_rate_limited?(self.user)}",
      "tfa_enabled:#{T.must(user).two_factor_authentication_enabled?}",
    ]

    GitHub.dogstats.increment("account_security.authentication_records.unexpected_login", tags: tags)
  end

  # Public: Alert for completed (non-2FA) sign ins.
  def deliver_unexpected_sign_in_notification
    if web_sign_in? && deliver_sign_in_notification?
      AccountMailer.unexpected_sign_in(self).deliver_later
    end
  end

  # For sign ins that see a two factor challenge, we set a job to checks
  # whether or not the login eventually succeeded.
  def queue_partial_authentication_followup
    if self.flagged_reason && # only follow up on anomalous results
        deliver_sign_in_notification? &&  # filter opt outs, employee hosts, etc...
        two_factor_partial_sign_in? # only 2FA partial events should be analyzed

      # Pass along the current email addresses. This job runs 10 minutes later
      # and an attacker could have updated the email addresses.
      primary_email = T.must(self.user).email
      bcc_emails = T.must(self.user).account_related_emails.map(&:to_s) - [primary_email]
      PartialTwoFactorAuthenticationNotificationJob.set(wait: TWO_FACTOR_LENIENCY).perform_later(self, primary_email, bcc_emails)
    end
  end

  def normalize_user_agent
    self.user_agent = T.must(self.user_agent.dup).force_encoding("US-ASCII").scrub[0, 255] if self.user_agent
  end
end
