# typed: true
# frozen_string_literal: true

class DeviceAuthorizationGrant < ApplicationRecord::Domain::IntegrationsCollab

  DEVICE_CODE_BYTES = 20
  USER_CODE_BYTES = 4

  DEVICE_CODE_LAST_EIGHT_PATTERN = /\A[a-f0-9]{8}\z/
  HASHED_DEVICE_CODE_PATTERN     = /\A[A-Za-z0-9+\/=]{44}\z/
  USER_CODE_PATTERN              = /\A[A-Z0-9]{4}\-[A-Z0-9]{4}\z/

  # The minimum amount of time in seconds that the client
  # needs to wait between polling requests to the token endpoint.
  INTERVAL = 5

  # Internal: The amount of time in minutes before the grant is expired
  EXPIRATION_WINDOW = 15.minutes

  # https://tools.ietf.org/html/rfc8628#section-3.4
  GRANT_TYPE = "urn:ietf:params:oauth:grant-type:device_code"

  VALID_APPLICATION_TYPES = %w(Integration OauthApplication)

  belongs_to :application, polymorphic: true, required: true
  belongs_to :oauth_access

  validates :application_type, inclusion: VALID_APPLICATION_TYPES

  validates :expires_at, presence: true

  validates :device_code_last_eight, allow_nil: true, format: { with: DEVICE_CODE_LAST_EIGHT_PATTERN }, length: { is: 8 }

  validates :hashed_device_code, allow_nil: true, format: { with: HASHED_DEVICE_CODE_PATTERN }, length: { is: 44 }, uniqueness: { case_sensitive: true }

  validates :ip, length: { maximum: 40 }, presence: true

  validates :user_code,
    format: { with: USER_CODE_PATTERN, allow_nil: true },
    length: { is: 9, allow_nil: true },
    uniqueness: { case_sensitive: false, allow_nil: true }

  validates_presence_of :user_code, on: :create

  serialize :scopes, coder: JSON

  attribute :expires_at, :utc_timestamp

  before_validation :initialize_expires_at, on: :create
  before_validation :initialize_user_code,  on: :create

  # This should be a has_one through, but because
  # we can't perform a join we need to delegate.
  delegate :user, to: :oauth_access

  scope :unclaimed, -> {
    where(oauth_access: nil)
  }

  extend GitHub::Encoding
  force_utf8_encoding :hashed_device_code

  def self.hash_for(code)
    Digest::SHA256.base64digest(code.to_s)
  end

  def claimed?
    oauth_access.present?
  end

  # Public: Returns the number of seconds until this grant's expiration
  #
  # Returns an Integer.
  def expires_in
    (expires_at - Time.zone.now).floor
  end

  # Public: Is this record no longer valid
  # due to it's expiry?
  #
  # Returns a Boolean.
  def expired?
    expires_in <= 0
  end

  def integration_application_type?
    application_type == "Integration"
  end

  # Public: Get the location from where the device code was requested.
  #
  # Returns a Hash containing as much location information as was available.
  def location
    return @location if defined?(@location)
    @location = GitHub::Location.look_up(self.ip)
  end

  def oauth_application_type?
    application_type == "OauthApplication"
  end

  def redeem_device_code!
    device_code        = SecureRandom.hex(DEVICE_CODE_BYTES)
    hashed_device_code = self.class.hash_for(device_code)

    update!(hashed_device_code: hashed_device_code, device_code_last_eight: device_code.last(8))

    device_code
  end

  def scopes=(new_scopes)
    return unless oauth_application_type?
    super(OauthAccess.normalize_scopes(Array(new_scopes), visibility: :all))
  end

  private

  def initialize_expires_at
    self.expires_at = EXPIRATION_WINDOW.from_now
  end

  def initialize_user_code
    self.user_code = SecureRandom.hex(USER_CODE_BYTES).upcase.insert(4, "-")
  end
end
