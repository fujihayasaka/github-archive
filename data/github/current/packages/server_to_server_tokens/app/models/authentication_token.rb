# typed: true
# frozen_string_literal: true

# Public: An expiring, persisted token for use in making authenticated
# requests.
class AuthenticationToken < ApplicationRecord::Domain::IntegrationsLodge
  include ServerToServerTokens::IAuthenticationToken
  attr_accessor :valid_after

  # Internal: The amount of time in seconds before the token is expired.
  EXPIRATION_WINDOW = 1.hour

  # Backoff set to pass in
  BACKOFF_SET = [0.1, 0.2, 0.4]

  # The prefix for the token.
  TOKEN_PREFIX = "ghs_"
  TOKEN_PREFIX_LENGTH = 4
  TOKEN_CHECKSUM_LENGTH = 6

  # Require token_last_eight to be a 8 hex character string
  TOKEN_LAST_EIGHT_PATTERN = /\A[a-zA-Z0-9]{8}\z/

  HASHED_TOKEN_DIGEST = Digest::SHA256

  TOKEN_BYTES = 30

  CREATE_FOR_STATS_KEY = "authentication_token.create_for"
  UNKNOWN_CODE_PATH = "unknown"

  belongs_to :authenticatable, polymorphic: true, required: true, validate: true
  validates :authenticatable_id, presence: true
  validates :authenticatable_type, presence: true, inclusion: { in: %w[IntegrationInstallation ScopedIntegrationInstallation SiteScopedIntegrationInstallation] }

  validates_presence_of :hashed_value
  validates_length_of :hashed_value, maximum: 255

  # Public: String last eight characters of token.
  # column :token_last_eight
  validates_format_of :token_last_eight, with: TOKEN_LAST_EIGHT_PATTERN, allow_nil: true

  before_create :initialize_expires_at_timestamp
  attribute :expires_at_timestamp, :utc_timestamp

  extend GitHub::Encoding
  force_utf8_encoding :hashed_value

  scope :with_unhashed_token, ->(token) {
    return none if token.blank?

    hashed_value = hash_token(token)
    where(hashed_value: hashed_value)
  }

  scope :active, -> {
    where("authentication_tokens.expires_at_timestamp > ?", Time.zone.now.to_i)
  }

  def self.hash_token(token)
    HASHED_TOKEN_DIGEST.base64digest(token)
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

  # Public: Create an AuthenticationToken.
  #
  # authenticatable - The object that this token will belong to.
  #
  # Returns a tuple of the AuthenticationToken and the plaintext token String
  #   for use in making authenticated requests.
  def self.create_for(authenticatable_id, authenticatable_type, span_attributes, code_path: UNKNOWN_CODE_PATH)
    GitHub.tracer.in_span("AuthenticationToken.create_for", kind: :internal) do |span|
      token_value, hashed_token = generate_random_token_pair
      last_operations = DatabaseSelector::LastOperations.from_token(token_value)
      ActiveRecord::Base.connected_to(role: :writing) do
        token_record = create!(
          authenticatable_id: authenticatable_id,
          authenticatable_type: authenticatable_type,
          hashed_value: hashed_token,
          token_last_eight: token_value.last(8),
        )

        ActiveRecord::Base.connected_to(role: :reading) do
          span.add_attributes(span_attributes)
        end

        GitHub.dogstats.increment(CREATE_FOR_STATS_KEY, tags: [
          "code_path:#{code_path}", "authenticatable_type:#{authenticatable_type}"
        ])

        last_operations.store_latest_writes
        [token_record, token_value]
      end
    end
  end

  def self.generate_random_token_pair
    random_token = SecureRandom.alphanumeric(TOKEN_BYTES)
    full_token = TOKEN_PREFIX + random_token + checksum(random_token)
    [full_token, hash_token(full_token)]
  end

  def self.checksum(token)
    crc_value = Zlib.crc32(token)
    Base62.encode(crc_value, min_length: 6)
  end

  class ExtensionResult
    def self.success; new(:success); end
    def self.failed(reason); new(:failed, reason); end

    REASON_MESSAGES = {
      end_of_life: "This access token's expires_at time cannot be extended further.",
      expires_at_too_long: "This access token's expires_at time cannot be extended by more than 60 minutes.",
      expires_at_in_past: "This access token's expires_at time cannot be in the past."
    }

    attr_reader :reason, :status

    def initialize(status, reason = nil)
      @status = status
      @reason = reason
    end

    def success?
      status == :success
    end

    def failure?
      !success?
    end

    def message
      REASON_MESSAGES.fetch(reason, "Unknown")
    end
  end

  # Internal: extend the expires_at_timestamp for an AuthenticationToken
  # record.
  #
  # record      - AuthenticationToken record to extend.
  # expires_at  - String (Timestamp) the new expires_at timestamp for the
  #               record
  #
  # Returns an ExtensionResult object.
  def self.extend_expires_at(record, expires_at, entry_point:)
    extended_expires_at_timestamp =
      if expires_at.present?
        Time.parse(expires_at)
      else
        EXPIRATION_WINDOW.from_now
      end

    if extended_expires_at_timestamp > (record.created_at + 24.hours)
      return ExtensionResult.failed(:end_of_life)
    elsif extended_expires_at_timestamp > EXPIRATION_WINDOW.from_now
      return ExtensionResult.failed(:expires_at_too_long)
    elsif extended_expires_at_timestamp <= Time.now
      return ExtensionResult.failed(:expires_at_in_past)
    end

    ActiveRecord::Base.connected_to(role: :writing) do
      transaction do
        record.update!(expires_at_timestamp: extended_expires_at_timestamp)

        authenticatable = record.authenticatable
        if authenticatable.respond_to?(:extend_expires_at) && authenticatable.expires_at.present?
          # Ensure the authenticatable does not expire before the token expires
          extended_expires_at_for_authenticatable = [
            extended_expires_at_timestamp,
            authenticatable.expires_at,
          ].max

          record.authenticatable.extend_expires_at(extended_expires_at_for_authenticatable, entry_point: entry_point)
        end
      end
    end

    ExtensionResult.success
  end

  def expired?
    return false if expires_at_timestamp.nil?

    T.must(self.expires_at_timestamp) <= Time.zone.now
  end

  private

  # Private: Sets the expires_at time which is used to automatically
  # invalidate tokens after a certain amount of time.
  #
  # Returns the expiration DateTime.
  def initialize_expires_at_timestamp
    self.expires_at_timestamp ||= EXPIRATION_WINDOW.from_now
  end
end
