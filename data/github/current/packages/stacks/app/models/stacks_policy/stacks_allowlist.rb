# typed: false
# frozen_string_literal: true

class StacksPolicy::StacksAllowlist < ApplicationRecord::Collab
  self.table_name = "stacks_allowlists"

  VALID_ENTITIES = %w(Business User Repository)

  belongs_to :entity, polymorphic: true
  # rubocop:todo Rails/InverseOf
  has_many :allowed_stacks_patterns, foreign_key: :stacks_allowlist_id, class_name: "StacksPolicy::AllowedStacksPattern", dependent: :delete_all
  # rubocop:enable Rails/InverseOf

  MAXIMUM_PATTERNS = 75
  MAX_THROTTLE_RETRIES = 5

  validates :entity_type, inclusion: { in: VALID_ENTITIES }
  validates :entity_id, uniqueness: { scope: :entity_type }

  def self.to_rank(allowlist)
    return 0 if allowlist.blank?
    return 1 if allowlist.includes_specific_stacks?
    2  # this means local only
  end

  def self.update_or_create_with_patterns(entity, patterns:, actor:)
    StacksPolicy::StacksAllowlist.transaction do
      allowlist = StacksPolicy::StacksAllowlist.find_by(entity: entity) || StacksPolicy::StacksAllowlist.create(entity: entity)

      if patterns.length > MAXIMUM_PATTERNS
        allowlist.errors.add(:specified_stacks, "cannot be set to more than #{MAXIMUM_PATTERNS}")
      else
        allowlist.set_allowed_stack_patterns(patterns, actor: actor)
      end

      allowlist
    end
  end

  def local_stacks_only?
    !includes_specific_stacks?
  end

  def includes_specific_stacks?
    verified_allowed? || specified_patterns?
  end

  def specified_patterns?
    allowed_stacks_patterns.any?
  end

  def enable_local_stacks_only
    allowed_stacks_patterns&.delete_all
    update(verified_allowed: false)
  end

  def enable_specified_stacks(verified: nil, patterns: nil, actor:)
    self.verified_allowed = verified unless verified.nil?
    save

    set_allowed_stack_patterns(patterns, actor: actor)
  end

  def set_allowed_stack_patterns(patterns, actor:)
    return unless patterns
    allowed_stacks_patterns.delete_all unless self.new_record?
    patterns_as_hashes = patterns
      .first(MAXIMUM_PATTERNS)
      .map { |value| build_allowed_stack_pattern(value) }
      .compact

    StacksPolicy::AllowedStacksPattern.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
      StacksPolicy::AllowedStacksPattern.insert_all(patterns_as_hashes) unless patterns_as_hashes.empty?
    end

  end

  def build_allowed_stack_pattern(value)
    record = StacksPolicy::AllowedStacksPattern.new(
      stacksallowlist: self,
      value: value,
      created_at: Time.now.utc,
      updated_at: Time.now.utc
    )

    return record.attributes if record.valid?

    self.errors.add(:specified_stacks, "#{value} #{record.errors.first&.message}")
    nil
  end
end
