# typed: true
# frozen_string_literal: true

# rubocop:disable GitHub/DatabaseModelsShouldHaveTests
# Justification: we will remove this class entirely after 3.17 branches off
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

  validate :only_allow_disable_existing

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
    # Tag protections are fully deprecated and disabled.
    false
  end

  def wildcard?
    pattern == "*"
  end

  def matches?(tag)
    File.fnmatch?(pattern, tag, File::FNM_PATHNAME)
  end

  # This is a temporary measure to allow unit tests to continue to run until we remove this code entirely.
  # Otherwise there's no way for tests to create the tag protection records in order to test them.
  # DO NOT CALL THIS FROM ACTUAL CODE, it's just here to allow test code to create tag protections in order
  # to confirm they're not being enforced.
  # rubocop:disable Style/ClassVars
  # Justification: This cannot be implemented as an instance var
  @@allow_tag_creation_for_tests = false

  def self.allow_creation_for_tests(&block)
    @@allow_tag_creation_for_tests = true
    yield
    @@allow_tag_creation_for_tests = false
  end

  private

  def only_allow_disable_existing
    # The only allowed change at this point is disabling an existing tag protection rule (the migration job needs this to work).
    return if self.enabled_was == true && self.enabled == false
    return if @@allow_tag_creation_for_tests

    errors.add(:repository, "tag protections have been fully deprecated")
  end
end
