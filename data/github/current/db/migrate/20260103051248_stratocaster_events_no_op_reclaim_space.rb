# typed: true

class StratocasterEventsNoOpReclaimSpace < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::Stratocaster)

  def change
    # We want to cautiously skip production GHES and multi-tenant enterprise
    return if (GitHub.enterprise? || GitHub.multi_tenant_enterprise?) && Rails.env.production? # rubocop:disable GitHub/DoNotBranchOnRailsEnv
    # This migration is a no-op to force a rewrite of the table to reclaim disk space
    change_column_comment(
      :stratocaster_events,
      :id,
      from: "The primary ID",
      to: "The primary key ID",
    )
  end
end
