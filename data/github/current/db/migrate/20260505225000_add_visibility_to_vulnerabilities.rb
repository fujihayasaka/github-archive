# typed: true
# frozen_string_literal: true

# Adds an integer-backed `visibility` column alongside the existing
# `visibility_scope` varchar(20) column. This is step 1 of the staged conversion
# tracked in github/team-advisory-database#6358:
#   1. Add `visibility` column. (this PR)
#   2. Dual-write from the model.
#   3. Backfill existing rows via data transition.
#   4. Switch reads, drop legacy column, declare Rails enum.
#
# The column defaults to `0` (open_source) so existing rows have a safe value
# without requiring a backfill write per row, and so writes from code paths
# that don't yet populate it succeed. The legacy `visibility_scope` column
# remains the source of truth until a later step.
class AddVisibilityToVulnerabilities < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::Vulnerabilities)

  def change
    add_column :vulnerabilities, :visibility, :integer,
      limit: 1, null: false, default: 0,
      comment: "0=open_source, 1=innersource; mirrors visibility_scope during transition"
  end
end
