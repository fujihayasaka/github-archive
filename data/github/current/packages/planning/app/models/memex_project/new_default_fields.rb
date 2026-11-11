# typed: strict
# frozen_string_literal: true

# This module centralizes the logic for handling the new default fields
# (sub-issues-progress and linked-pull-requests).
module MemexProject::NewDefaultFields
  # New default field names
  FIELD_NAMES = T.let([
    MemexProjectColumn::SUB_ISSUES_PROGRESS_COLUMN_NAME,
    MemexProjectColumn::LINKED_PULL_REQUESTS_COLUMN_NAME
  ].freeze, T::Array[String])

  # Returns true (the new default fields are always enabled)
  sig { params(creator: T.nilable(User)).returns(T::Boolean) }
  def self.enabled_for?(creator)
    return false unless creator
    true
  end

  # Returns the field names that should be included
  sig { params(creator: T.nilable(User)).returns(T::Array[String]) }
  def self.field_names_when_enabled(creator)
    return [] unless creator
    FIELD_NAMES.dup
  end

  # Returns the field name slugs that should be included
  sig { params(creator: T.nilable(User)).returns(T::Array[String]) }
  def self.field_slugs_when_enabled(creator)
    return [] unless creator
    FIELD_NAMES.map { |name| MemexProjectColumn.generate_name_slug(name) }
  end

  # No-op: fields are no longer filtered from templates
  sig { params(template: T::Hash[Symbol, T.untyped], creator: T.nilable(User)).void }
  def self.filter_template_fields!(template, creator)
    # No longer filters fields - all new default fields are always included
  end
end
