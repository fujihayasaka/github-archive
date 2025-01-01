# typed: true
# frozen_string_literal: true

# Public: An expiring, persisted token for use in making authenticated
# requests.
class AuthenticationToken < ApplicationRecord::Domain::IntegrationsLodge
  include AccessTokenGeneratable

  self.access_token_prefix = "ghs_"
  attr_accessor :valid_after

  # Public: The Regexp describing the format of an AuthenticationToken's string
  # token value.
  TOKEN_PATTERN_GS1 = %r{
    \A                              # start
    #{self.access_token_prefix}     # the token format prefix
    [a-zA-Z0-9]{36}                 # the random portion and checksum
    \z                              # end
  }xi

  # legacy pattern
  TOKEN_PATTERN_V1 = %r{
    \A                 # start
    v1                 # the token format version
    \.                 # a period
    [a-f0-9]{40}       # the random portion of the token
    \z                 # end
  }xi

  # Internal: The amount of time in seconds before the token is expired.
  EXPIRATION_WINDOW = 1.hour

  # Backoff set to pass in
  BACKOFF_SET = [0.1, 0.2, 0.4]

  # Require token_last_eight to be a 8 hex character string
  TOKEN_LAST_EIGHT_PATTERN = /\A[a-zA-Z0-9]{8}\z/

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

  # Public: Create an AuthenticationToken.
  #
  # authenticatable - The object that this token will belong to.
  #
  # Returns a tuple of the AuthenticationToken and the plaintext token String
  #   for use in making authenticated requests.
  def self.create_for(authenticatable, code_path: UNKNOWN_CODE_PATH)
    GitHub.tracer.in_span("AuthenticationToken.create_for", kind: :internal) do |span|
      token_value, hashed_token = generate_random_token_pair

      last_operations = DatabaseSelector::LastOperations.from_token(token_value)
      ActiveRecord::Base.connected_to(role: :writing) do
        token_record = create!(
          authenticatable: authenticatable,
          hashed_value: hashed_token,
          token_last_eight: token_value.last(8),
        )

        ActiveRecord::Base.connected_to(role: :reading) do
          span.add_attributes(create_for_span_attributes(authenticatable))
        end

        GitHub.dogstats.increment(CREATE_FOR_STATS_KEY, tags: [
          "code_path:#{code_path}", "authenticatable_type:#{authenticatable.class.name}"
        ])

        last_operations.store_latest_writes
        [token_record, token_value]
      end
    end
  end

  # Public: Checks if the given token matches the AuthenticationToken pattern
  #
  # token - The string to check
  #
  # Returns true if token follows the AuthenticationToken pattern,
  #   false if it doesn't
  def self.matches_pattern?(token)
    !!(token =~ AuthenticationToken::TOKEN_PATTERN_V1 ||
       token =~ AuthenticationToken::TOKEN_PATTERN_GS1)
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

  # Internal: Obtain all of the available attributes for `authenticatable` that
  # we can send to Datadog.
  #
  # Returns a Hash.
  private_class_method def self.create_for_span_attributes(authenticatable)
    span_attributes = {
      "gh.authentication_token.authenticatable.id" => authenticatable.id,
      "gh.authentication_token.authenticatable.type" => authenticatable.class.name,
    }

    if authenticatable.respond_to?(:target_id) && authenticatable.respond_to?(:target_type)
      span_attributes["gh.installation.target.id"] = authenticatable.target_id
      span_attributes["gh.installation.target.type"] = authenticatable.target_type
    end

    if authenticatable.respond_to?(:parent)
      span_attributes["gh.parent_installation.id"] = authenticatable.parent.id
    end

    if authenticatable.respond_to?(:integration)
      integration = authenticatable.integration
      span_attributes["gh.integration.id"] = integration.id
    end

    span_attributes
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
