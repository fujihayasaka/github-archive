# typed: false
# frozen_string_literal: true

class ActionsPolicy::Allowlist < ApplicationRecord::Collab
  include GitHub::Memoizer

  self.table_name = "actions_allowlists"

  # We have to save the base model of the entities in order for polymorphic
  # associations to work. This means that when we store an allowlist for an
  # organization, it's going down as a `User` in the database.
  VALID_ENTITIES = %w(Business User Repository)

  belongs_to :entity, polymorphic: true
  # rubocop:todo Rails/InverseOf
  has_many :allowed_action_patterns, foreign_key: :actions_allowlist_id, class_name: "ActionsPolicy::AllowedActionPattern", dependent: :delete_all
  # rubocop:enable Rails/InverseOf

  MAXIMUM_PATTERNS = 1000

  # If given patterns are more than 100, then we will update them via background job
  MINIMUM_PATTERNS_FOR_ASYNC_UPDATE = 100

  MAX_THROTTLE_RETRIES = 5

  validates :entity_type, inclusion: { in: VALID_ENTITIES }
  validates :entity_id, uniqueness: { scope: :entity_type }

  after_commit :emit_allowlist_modified_metric

  def self.to_rank(allowlist)
    return 0 if allowlist.blank? || allowlist.all_allowed?
    return 1 if allowlist.includes_specific_actions?
    2  # this means local only
  end

  def self.update_or_create_with_patterns(entity, patterns:, actor:)
    # remove duplicate patterns
    patterns = patterns.uniq

    ActionsPolicy::Allowlist.transaction do
      allowlist = ActionsPolicy::Allowlist.find_by(entity: entity) || ActionsPolicy::Allowlist.create(entity: entity)

      if patterns.length > MAXIMUM_PATTERNS
        allowlist.errors.add(:specified_actions, "cannot be set to more than #{MAXIMUM_PATTERNS}")
      else
        allowlist.set_allowed_action_patterns(patterns, actor: actor)
      end

      allowlist
    end
  end

  def local_only?
    !includes_specific_actions? && !all_allowed?
  end

  def includes_specific_actions?
    github_owned_allowed? || verified_allowed? || specified_patterns?
  end

  def specified_patterns?
    allowed_action_patterns.any?
  end

  def enable_all(sha_pinning: nil)
    sha_pinning = self.sha_pinning_required if sha_pinning.nil?

    if sha_pinning
      delete_all_patterns

      update(
        all_allowed: true,
        github_owned_allowed: false,
        verified_allowed: false,
        sha_pinning_required: sha_pinning,
      )
    else
      self.destroy
    end
  end

  def enable_local_only(sha_pinning: nil)
    sha_pinning = self.sha_pinning_required if sha_pinning.nil?

    delete_all_patterns

    update(
      all_allowed: false,
      github_owned_allowed: false,
      verified_allowed: false,
      sha_pinning_required: sha_pinning,
    )
  end

  def enable_specified_actions(github_owned: nil, verified: nil, patterns: nil, sha_pinning: nil, actor:)
    self.all_allowed = false
    self.github_owned_allowed = github_owned unless github_owned.nil?
    self.verified_allowed = verified unless verified.nil?
    self.sha_pinning_required = sha_pinning unless sha_pinning.nil?
    save

    set_allowed_action_patterns(patterns, actor: actor)

    if !github_owned.nil? || !verified.nil? || !sha_pinning.nil?
      entity.instrument "update_actions_settings",
        actor:                        actor,
        updated_github_owned_allowed: github_owned,
        updated_verified_allowed:     verified,
        updated_sha_pinning_required: sha_pinning
    end
  end

  def set_allowed_action_patterns(patterns, actor:)
    return unless patterns

    # find the common patterns and delete the stale ones.
    existing_patterns = allowed_action_patterns&.map(&:value) || []
    common_patterns = existing_patterns & patterns
    delete_patterns = existing_patterns - common_patterns

    # create only new ones from the given patterns
    patterns -= common_patterns

    if delete_patterns.any?
      emit_patterns_modified_metric("destroy", entity_type, delete_patterns.length)
    end

    if patterns.any?
      emit_patterns_modified_metric("create", entity_type, patterns.length)
    end

    # trigger background job
    if delete_patterns.length > MINIMUM_PATTERNS_FOR_ASYNC_UPDATE || patterns.length > MINIMUM_PATTERNS_FOR_ASYNC_UPDATE
      delete_pattern_ids = allowed_action_patterns.filter_map { |pattern| pattern.id if delete_patterns.include?(pattern.value) }
      maximum_patterns_allowed = ActionsPolicy::Allowlist::MAXIMUM_PATTERNS - common_patterns.length
      new_valid_patterns = patterns
        .first(maximum_patterns_allowed)
        .filter_map { |value| value if build_allowed_action_pattern(value) }
      Actions::UpdateActionsPatternsJob.perform_later(self.id, delete_pattern_ids, new_valid_patterns)
    else
      delete_pattern_items = allowed_action_patterns.where(value: delete_patterns)
      update_patterns_directly(delete_pattern_items, patterns, MINIMUM_PATTERNS_FOR_ASYNC_UPDATE)
    end

    entity.instrument "update_actions_settings",
      actor:                        actor,
      updated_patterns:             true
  end

  # Updates patterns directly without background job
  def update_patterns_directly(delete_patterns, new_patterns, limit)
    delete_patterns.delete_all unless delete_patterns.empty?

    patterns_as_hashes = new_patterns
      .first(limit)
      .map { |value| build_allowed_action_pattern(value) }
      .compact

    ActionsPolicy::AllowedActionPattern.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
      ActionsPolicy::AllowedActionPattern.insert_all(patterns_as_hashes) unless patterns_as_hashes.empty?
    end
  end

  # Returns the hash form of active record object for the given pattern value
  # and returns nil if the pattern is invalid and marks the error for allowlist object
  def build_allowed_action_pattern(value)
    record = ActionsPolicy::AllowedActionPattern.new(
      allowlist: self,
      value: value,
      created_at: Time.now.utc,
      updated_at: Time.now.utc
    )

    return record.attributes if record.valid?

    self.errors.add(:specified_actions, "#{value} #{record.errors.first&.message}")
    nil
  end



  private

  def delete_all_patterns
    emit_patterns_modified_metric("destroy", entity_type, allowed_action_patterns.length)

    if allowed_action_patterns.length > MINIMUM_PATTERNS_FOR_ASYNC_UPDATE
      delete_pattern_ids = allowed_action_patterns.map(&:id)
      Actions::UpdateActionsPatternsJob.perform_later(self.id, delete_pattern_ids, [])
    else
      allowed_action_patterns&.delete_all
    end
  end

  def emit_allowlist_modified_metric
    if transaction_include_any_action?([:create])
      action = "create"
    elsif transaction_include_any_action?([:update])
      action = "update"
    elsif transaction_include_any_action?([:destroy])
      action = "destroy"
    else
      return
    end

    GitHub.dogstats.increment(
      "actions.allowed_actions_policy.modified",
      tags: [
        "action:#{action}",
        "policy:#{determine_policy_type}",
        "sha_pinning_required:#{!!sha_pinning_required?}",
        "github_owned_allowed:#{!!github_owned_allowed?}",
        "verified_allowed:#{!!verified_allowed?}",
        "entity:#{entity_type}"
      ]
    )
  end

  def determine_policy_type
    return "all" if all_allowed?
    return "local_only" if local_only?
    "specified"
  end

  def emit_patterns_modified_metric(action, entity, count)
    GitHub.dogstats.count(
      "actions.allowed_actions_policy.patterns.modified",
      count,
      tags: [
        "action:#{action}",
        "entity:#{entity}",
      ]
    )
  end
end
