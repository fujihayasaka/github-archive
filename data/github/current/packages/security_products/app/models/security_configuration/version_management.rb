# typed: strict
# frozen_string_literal: true

# Bumps the `version` column whenever a SecurityConfiguration is updated in a
# way that would require reapplication to attached repositories. The version is
# used by the attachment pipeline to detect stale in-flight work and avoid
# wasted effort.
#
# Cosmetic changes (name, description, etc.) do NOT bump the version.
#
# See:
# - https://github.com/github/security-products-enablement/issues/2787
# - https://github.com/github/security-products-enablement/blob/main/docs/adrs/2026-03-18-security-configuration-attachment-pipeline.md
module SecurityConfiguration::VersionManagement
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { SecurityConfiguration }

  # Cosmetic / bookkeeping attributes that do NOT bump `version`.
  #
  # We use a denylist so that newly-added feature columns are version-triggering
  # by default. The failure mode of an extra bump (one redundant apply job) is
  # safe; the failure mode of a missed bump (silent drift) is not.
  #
  # Only add to this list when the attribute is provably irrelevant to what
  # gets applied to repositories.
  VERSION_IGNORED_ATTRIBUTES = T.let(%w[
    id
    name
    description
    target_type
    target_id
    created_at
    updated_at
    version
  ].freeze, T::Array[String])

  included do
    T.bind(self, T.class_of(SecurityConfiguration))
  end

  # Atomically increments this row's `version` column and mirrors the new
  # value onto the in-memory record. Returns `true` if the row was found and
  # bumped, `false` if no row matched (e.g. it was deleted concurrently).
  #
  # Uses MySQL's `LAST_INSERT_ID(expr)` trick to capture the post-increment
  # value as part of the same `UPDATE`, so the returned integer is exactly
  # what this statement assigned even under concurrent bumps from other
  # writers. See `Actions::WorkflowSequence.next` for the same idiom.
  #
  # See: https://github.com/github/security-products-enablement/issues/2787
  sig { returns(T::Boolean) }
  def bump_version
    rows_updated = SecurityConfiguration.where(id: id).update_all("version = LAST_INSERT_ID(version + 1)")
    return false if rows_updated.zero?

    # Mirror the persisted value onto this in-memory record so callers reading
    # `version` after the save see the new value.
    self.version = T.cast(SecurityConfiguration.connection.send(:last_insert_id), Integer)
    # `self.version = ...` marks `version` as dirty in AR's change tracking.
    # If we leave it dirty, a subsequent `save` (or any callback chain that
    # triggers one) will issue a redundant `UPDATE ... SET version = N` and
    # could overwrite a higher value written by a concurrent bump. Mark it
    # clean again so AR knows it matches the row.
    clear_attribute_changes([:version])
    true
  end

  private

  sig { returns(T::Boolean) }
  def meaningful_change?
    (saved_changes.keys - VERSION_IGNORED_ATTRIBUTES).any?
  end
end
