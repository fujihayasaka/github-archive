# typed: true
# frozen_string_literal: true

# Drops the legacy `visibility_scope` varchar column from `vulnerabilities`.
# Final step of github/team-advisory-database#6358. The integer-backed
# `visibility` enum has been the source of truth since github/github#431555,
# and the previous PR added the column to `ignored_columns` so Rails stopped
# selecting it. Datadog confirmed zero queries against the column before this
# was merged.
#
# `Vulnerability#visibility_scope` continues to work via the model's
# `alias_attribute`, keeping the public REST JSON key and any external
# callers functioning without a schema column.
class RemoveVisibilityScopeFromVulnerabilities < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::Vulnerabilities)

  def change
    remove_column :vulnerabilities, :visibility_scope, :string,
      limit: 20, null: false, default: "open_source",
      comment: "open_source or innersource"
  end
end
