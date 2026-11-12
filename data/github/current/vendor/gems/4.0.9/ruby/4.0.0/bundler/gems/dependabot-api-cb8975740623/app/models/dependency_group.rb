# frozen_string_literal: true

class DependencyGroup < ApplicationRecord
  # A group must define _at least one_ base rule.
  BASE_RULES = %w(
    dependency-type
    patterns
    update-types
    exclude-patterns
    group-by
  ).freeze

  # We sanitise the rule hash and only persist keys that are in this list in
  # addition to JSON schema validation so any DependencyGroups created via
  # backfills or migrations cannot persist unexpected data.
  PERMITTED_RULES = BASE_RULES + %w().freeze # Here's a little place to put more rules when we need to.

  # These rules are not available to users yet
  # (Currently empty because all rules are rolled out, but we may add more in
  # the future)
  EXPERIMENTAL_RULES = %w().freeze

  APPLIES_TO_VALUES = [
    APPLIES_TO_VERSION_UPDATES = "version-updates",
    APPLIES_TO_SECURITY_UPDATES = "security-updates",
  ].freeze

  belongs_to :update_config
  has_many :pull_requests

  validates :name,          presence: true, uniqueness: { scope: :update_config, conditions: -> { active } }
  validates :rules,         presence: true
  validates :update_config, presence: true
  validates :applies_to,    inclusion: {
    in: APPLIES_TO_VALUES,
    message: "%<value>s must be one of #{APPLIES_TO_VALUES.join(', ')}",
  }
  validates :sort_order, presence: true, numericality: { only_integer: true }, allow_nil: true

  validate :rules_are_a_permitted_hash

  serialize :rules, coder: JSON

  before_validation :format_name
  before_validation :filter_rules

  scope :active, -> { where(deleted_at: nil) }
  scope :ordered, -> { order(sort_order: :asc) }

  after_update_commit :enqueue_pr_cleanup, if: :update_has_deleted_group?

  before_destroy do
    throw(:abort)
  end

  # returns the rules attribute, filtering out experimental rules if required
  def enabled_rules
    rules.reject do |rule, _value|
      EXPERIMENTAL_RULES.include?(rule)
    end
  end

  def active?
    !deleted?
  end

  def deleted?
    deleted_at.present?
  end

  def delete
    return true if deleted?

    update!(deleted_at: Time.now.utc)
  end

  def applies_to
    super || APPLIES_TO_VERSION_UPDATES
  end

  def applies_to_security_updates?
    applies_to == APPLIES_TO_SECURITY_UPDATES
  end

  def sort_order
    super || nil
  end

  def serialize
    {
      "name" => name,
      "rules" => rules,
      "applies-to" => self[:applies_to],
    }.compact
  end

  def to_core
    Dependabot::DependencyGroup.new(name:, rules:, applies_to:)
  end

  private

  def format_name
    self.name = name&.parameterize
  end

  def filter_rules
    return unless rules.is_a?(Hash)

    self.rules = rules&.filter do |rule, _value|
      PERMITTED_RULES.include?(rule.to_s)
    end
  end

  def rules_are_a_permitted_hash
    if rules.is_a?(Hash)
      required_rules = BASE_RULES
      contains_at_least_one_required_rule = rules.keys.any? { |rule| required_rules.include?(rule.to_s) }
      unless contains_at_least_one_required_rule
        errors.add(:rules,
                   "must include one of '#{required_rules.join(', ')}'")
      end
    else
      errors.add(:rules, "must be a Hash")
    end
  end

  # This method checks ActiveRecord to determine if the most recent change to
  # attributes changed deleted_at from nil to a timestamp.
  def update_has_deleted_group?
    deleted_at_before, deleted_at_now = saved_change_to_attribute(:deleted_at)

    return false if deleted_at_now.blank? # the update didn't delete the group
    return false unless deleted_at_before.nil? # the group was already deleted

    true
  end

  def enqueue_pr_cleanup
    CleanupDependencyGroupPullRequestsJob.perform_later(id)
  end
end
