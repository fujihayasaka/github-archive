# typed: true
# frozen_string_literal: true

class RepositoryTagProtectionState < ApplicationRecord::Domain::Repositories
  self.table_name = "repository_tag_protection_states"
  belongs_to :repository, required: true, class_name: "Repository"

  attribute :pattern, default: "*"

  DOCS_URL = "https://docs.github.com/repositories/managing-your-repositorys-settings-and-features/managing-repository-settings/configuring-tag-protection-rules"
  IMPORT_DOCS_URL = "https://docs.github.com/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/creating-rulesets-for-a-repository#creating-a-branch-or-tag-ruleset"

  # Tag names can be split into different components (the parts between `/`).
  # This is a list of characters that can not be part of such a component for a rule.
  RULE_COMPONENT_CHARS = /[^\x00-\x1F\s\t\\:\^~\/]/
  VALID_RULE = /\A#{RULE_COMPONENT_CHARS}+(\/#{RULE_COMPONENT_CHARS}+)*\z/
  validates_format_of :pattern,
    with: VALID_RULE,
    message: "is invalid",
    allow_nil: false,
    allow_blank: false
  validates_uniqueness_of :pattern, scope: :repository_id

  validate :repo_supports_tag_protection

  scope :wildcard_first, -> { order(Arel.sql("CASE WHEN pattern = '*' THEN 0 ELSE 1 END")) }

  scope :by_pattern_length, -> { order(Arel.sql("CHAR_LENGTH(pattern)")) }

  # Public: Get a rule that matches the given tag
  #
  # - repo - Repository to get the rule for
  # - tag - Tag to match against. The unqualified tag name, without the leading `refs/tags/`.
  #
  # Returns a RepositoryTagProtectionState or nil.
  def self.for_tag(repo, tag)
    records = self.for_repository(repo)
    records.find { |r| r.wildcard? || r.matches?(tag) }
  end

  # Public: Get all rules for the given repository
  #
  # - repo - Repository to get the rule for
  #
  # Returns an array of RepositoryTagProtectionState
  def self.for_repository(repo)
    self.wildcard_first
        .by_pattern_length
        .where(repository_id: repo.id)
        .to_a
  end

  # Public: Given an array of RepositoryTagProtectionStates, check if
  # the given tag is protected by at least one of the rules.
  #
  # - tag_protection_states - Array of RepositoryTagProtectionStates,
  #                           usually from `RepositoryTagProtectionStates.for_repository`
  # - tag                   - String, the tag to check
  #
  # Returns a boolean
  def self.tag_is_protected?(tag_protection_states, tag)
    tag_protection_states.any? { |r| r.enabled && (r.wildcard? || r.matches?(tag)) }
  end

  def wildcard?
    pattern == "*"
  end

  def matches?(tag)
    File.fnmatch?(pattern, tag, File::FNM_PATHNAME)
  end

  private

  def repo_supports_tag_protection
    # Always allow disabling an existing tag protection rule. Only the migration job currently does this.
    return if self.enabled_was == true && self.enabled == false

    case repository&.tag_protections_availability
    when :disabled
      errors.add(:repository, "tag protections disabled")
    when :not_in_plan
      errors.add(:repository, "plan does not support tag protection")
    end
  end
end
