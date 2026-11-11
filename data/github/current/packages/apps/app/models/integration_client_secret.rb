# typed: true
# frozen_string_literal: true

class IntegrationClientSecret < ApplicationRecord::Domain::Integrations
  include GitHub::Validations

  belongs_to :integration, touch: true
  belongs_to :creator, class_name: "User"

  validates :integration, presence: true
  validates :creator, presence: true
  validates :secret_hash, presence: true
  validates :secret_last_eight, presence: true, unicode3: true
  validate :limit_secrets, on: :create

  before_validation :generate_secret, on: :create
  before_destroy :prevent_last_key_deletion

  after_destroy_commit :instrument_destroy

  attr_accessor :secret
  attr_accessor :bypass_secrets_limit

  ACCESS_THROTTLING = 1.week
  ACCESS_CUTOFF_DATE = Time.utc(2020, 10, 29)
  MAX_SECRETS = 5
  RECENTNESS = 1.week

  def self.hash_for(secret)
    Digest::SHA256.base64digest(secret.to_s)
  end

  def self.last_accessed_memcache_key(id)
    "integration_client_secret:last_accessed:#{id}"
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
      IntegrationClientSecretAccessJob.perform_later(id, now.to_i)
    end

    GitHub.instrument "integration_client_secret.access", integration_client_secret_id: id
  end

  def access
    self.class.access(id: id, last_accessed_at: accessed_at)
  end

  def access!(time)
    return if self.class.accessed_within_throttling_period?(accessed_at: accessed_at)

    ActiveRecord::Base.connected_to(role: :writing) do
      threshold = ACCESS_THROTTLING.ago.to_formatted_s(:db)
      self.class.connection.update(Arel.sql(<<-SQL, id: id, accessed_at: time, threshold: threshold))
        UPDATE integration_client_secrets SET accessed_at = :accessed_at
        WHERE id = :id AND (accessed_at < :threshold OR accessed_at IS NULL)
      SQL
    end

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

  private

  def instrument_destroy
    T.must(integration).instrument :remove_client_secret
  end

  def generate_secret
    return unless secret_hash.blank?
    self.secret = SecureRandom.hex(20)
    self.secret_last_eight = self.secret.last(8)
    self.secret_hash = self.class.hash_for(self.secret)
  end

  def prevent_last_key_deletion
    return if destroyed_by_association.present?
    if T.must(integration).client_secrets.where("id <> ?", id).none?
      errors.add :base, "You cannot delete the only secret. Generate a new secret first."
      throw :abort
    end
  end

  def limit_secrets
    if !bypass_secrets_limit && T.must(integration).client_secrets.count >= MAX_SECRETS
      errors.add(:size_limit, "Only #{MAX_SECRETS} client secrets are allowed per application.")
    end
  end
end
