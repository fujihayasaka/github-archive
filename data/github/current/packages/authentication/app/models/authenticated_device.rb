# typed: true
# frozen_string_literal: true

class AuthenticatedDevice < ApplicationRecord::Ballast
  include Instrumentation::Model

  attribute :display_name, StringFromBinary.new

  after_create_commit :instrument_create

  DEVICE_ID_REGEX = /\A[0-9a-f]{32}\z/

  # Throttle updates to the updated_at column for the current device.
  ACCESS_THROTTLE = 4.hours

  validates_format_of :device_id, with: DEVICE_ID_REGEX
  validates :user_id, presence: true, uniqueness: { scope: :device_id }

  belongs_to :user
  has_many :authentication_records

  has_many :two_factor_recovery_requests

  has_many :trusted_device_client_registrations, dependent: :delete_all
  has_many :trusted_devices, through: :trusted_device_client_registrations

  scope :verified, -> { where.not(approved_at: nil) }
  scope :unverified, -> { where(approved_at: nil) }

  def event_context(prefix: event_prefix)
    {
      prefix => display_name,
      "#{prefix}_id".to_sym => id,
    }
  end

  # Used for `device_id` values in cookies and database rows
  def self.generate_id
    SecureRandom.hex(16)
  end

  # Used to identify unverified devices via email
  def self.generate_device_verification_code
    6.times.map { SecureRandom.random_number(10) }.join
  end

  def self.generated_display_name(parsed_useragent)
    platform = case parsed_useragent&.platform&.name
    when "Macintosh"
      "macOS"
    when /Linux/
      "Linux"
    else
      parsed_useragent&.platform&.name
    end
    [parsed_useragent&.name, platform].compact.join(" on ").gsub(/[^a-z ]/i, "")
  end

  # updates the accessed_at field when necessary
  #
  # returns true when updates were made, nil if no update was necessary
  # raises an error if we're trying to `touch` a device that hasn't been saved
  def throttled_touch
    raise RuntimeError.new("Device must be persisted before it can be touched") if new_record?
    return unless accessed_at.nil? || accessed_at < ACCESS_THROTTLE.ago

    begin
      ActiveRecord::Base.connected_to(role: :writing) do
        touch(:accessed_at)
      end
    rescue ActiveRecord::ActiveRecordError => error
      # We will try again on the next request from this device, so there's
      # no need to return a 500 error if the ballast cluster's primary is down.
      GitHub.dogstats.increment("authenticated_device.throttled_touch.failed")
      Failbot.report(error)
    end
  end

  def verify!(display_name: nil)
    return true if verified?
    self.display_name = display_name if display_name
    self.approved_at = Time.current
    self.accessed_at = Time.current
    save!
  end

  def unverify(reason: :default)
    return true unless verified?
    self.update(approved_at: nil).tap do |success|
      GitHub.dogstats.increment("authenticated_device", tags: ["action:unverify", "reason:#{reason}"]) if success
    end
  end

  def verified?
    !!self.approved_at
  end

  def unverified?
    !verified?
  end

  # nil represents the state that the user has neither chosen to register nor
  # decline registration. It says nothing about whether they have been prompted
  # on the current device or not.
  def prompt_for_passkey_registration?
    self.trusted_device_available.nil?
  end

  # trusted_device_available is false when user has permanently declined passkeys from a device
  def declined_passkey_registration?
    !self.trusted_device_available.nil? && self.trusted_device_available == false
  end

  def has_authenticated_events?
    authentication_records.
      authenticated_events.
      where(user: user). # ensure we hit the index
      exists?
  end

  def self.find_device(user, device_id, database_query_role:)
    ActiveRecord::Base.connected_to(role: database_query_role) do
      user.authenticated_devices.find_by_device_id(device_id)
    end
  end

  def self.create_device!(user, device_id, display_name)
    ActiveRecord::Base.connected_to(role: :writing) do
      user.authenticated_devices.create!(
        device_id: device_id,
        display_name: display_name,
        accessed_at: Time.now,
      )
    end
  end

  # A race-condition safe method of creating or returning the current device.
  #
  # Returns a tuple [whether or not the device is new, the device found/created]
  def self.find_device_or_create!(user, device_id:, display_name:)
    # Try looking up the device in the read replica first.
    role ||= :reading

    device = find_device(user, device_id, database_query_role: role)
    return [false, device] if device

    # Try to create the device since we didn't find it in the read replica.
    [true, create_device!(user, device_id, display_name)]
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    raise if role == :writing

    role = :writing
    retry
  end

  # Public: Instrument new authenticated device creation.
  #
  # Returns nothing.
  def instrument_create
    T.must(self.user).instrument_unverified_device(:new_device_used, self)
  end
end
