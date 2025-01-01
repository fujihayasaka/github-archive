# typed: true

class NoopRacCheckSteps < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesActionsChecks)

  def change
    # Don't run this migration in production in GHES
    return if GitHub.enterprise? && Rails.env.production? # rubocop:disable GitHub/DoNotBranchOnRailsEnv

    # Noop migration to force a rewrite of the table to reclaim space from deleted rows
    change_column_comment(
      :check_steps,
      :id,
      from: nil,
      to: "The primary ID"
    )
  end
end
