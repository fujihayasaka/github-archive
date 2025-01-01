# typed: true
# frozen_string_literal: true

class AuthenticationLimitWhitelistEntry < ApplicationRecord::Domain::Users
  include GitHub::Validations
  belongs_to :creator, class_name: "User"

  validates_presence_of :metric, :value, :creator, :note, :expires_at
  validates :note, unicode3: true
  validates_uniqueness_of :value, scope: :metric, case_sensitive: false
  validate :metric_in_valid_metrics

  scope :active, -> (metric, value, at) {
    where(["metric = ? AND value = ? AND expires_at > ?", metric, value, at]).order("expires_at ASC")
  }

  # Public: Check if a metric/value pair is active at a given time.
  #
  # metric - The name of the ratelimit metric that has a whitelisted value.
  # value  - The metric value being whitelisted.
  #
  # Returns boolean.
  def self.whitelisted?(metric, value, at = Time.now)
    active(metric, value, at).exists?
  end

  # Public: Find a whitelist entry that is active at a given time.
  #
  # metric - The name of the ratelimit metric that has a whitelisted value.
  # value  - The metric value being whitelisted.
  # at     - The time at which the entry should be valid (default now).
  #
  # Returns a AuthenticationLimitWhitelistEntry instance.
  def self.find_active(metric, value, at = Time.now)
    active(metric, value, at).first
  end

  # Public: List of valid metrics.
  #
  # Returns a Array of Strings.
  def self.valid_metrics
    @valid_metrics ||= AuthenticationLimit.instances.map(&:data_key).uniq.map(&:to_s)
  end

  private

  # Private: Validation ensuring that there is a AuthenticationLimit using this
  # metric.
  #
  # Returns nothing. Adds an error unless valid.
  def metric_in_valid_metrics
    unless self.class.valid_metrics.include?(self.metric)
      valid_str = self.class.valid_metrics.join(", ")
      errors.add(:metric, "must be one of #{valid_str}")
    end
  end
end
