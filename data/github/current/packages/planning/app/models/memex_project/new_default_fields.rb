# typed: strict
# frozen_string_literal: true

# This module centralizes the logic for handling fields that are controlled by the
# memex_new_default_fields feature flag (currently sub-issues-progress and linked-pull-requests).
module MemexProject::NewDefaultFields
  # Fields that are controlled by the memex_new_default_fields feature flag
  FIELD_NAMES = T.let([
    MemexProjectColumn::SUB_ISSUES_PROGRESS_COLUMN_NAME,
    MemexProjectColumn::LINKED_PULL_REQUESTS_COLUMN_NAME
  ].freeze, T::Array[String])

  # Returns true if the memex_new_default_fields feature flag is enabled for the given creator
  sig { params(creator: T.nilable(User)).returns(T::Boolean) }
  def self.enabled_for?(creator)
    return false unless creator
    FeatureFlag.vexi.enabled?(:memex_new_default_fields, creator, default: false)
  end

  # Returns the field names that should be included when the feature flag is enabled,
  # or an empty array when disabled
  sig { params(creator: T.nilable(User)).returns(T::Array[String]) }
  def self.field_names_when_enabled(creator)
    enabled_for?(creator) ? FIELD_NAMES.dup : []
  end

  # Returns the field name slugs that should be included when the feature flag is enabled,
  # or an empty array when disabled
  sig { params(creator: T.nilable(User)).returns(T::Array[String]) }
  def self.field_slugs_when_enabled(creator)
    enabled_for?(creator) ? FIELD_NAMES.map { |name| MemexProjectColumn.generate_name_slug(name) } : []
  end

  # Removes new default fields from a template when the feature flag is disabled
  sig { params(template: T::Hash[Symbol, T.untyped], creator: T.nilable(User)).void }
  def self.filter_template_fields!(template, creator)
    return if enabled_for?(creator)

    field_slugs = FIELD_NAMES.map { |name| MemexProjectColumn.generate_name_slug(name) }

    template[:views]&.each do |view|
      if view[:visible_fields_by_name]
        field_slugs.each { |slug| view[:visible_fields_by_name].delete(slug) }
      end
    end
  end
end
