# typed: true

class StratocasterEventsNoOp < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Stratocaster)

  def change
    # We want to cautiously skip production GHES
    return if GitHub.enterprise? && Rails.env.production? # rubocop:disable GitHub/DoNotBranchOnRailsEnv

    # This migration is a no-op to force a rewrite of the table to reclaim disk space
    change_column_comment(
      :stratocaster_events,
      :id,
      from: nil,
      to: "The primary ID"
    )
  end
end
