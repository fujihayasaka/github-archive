# typed: true

require "github/transitions/20220330231603_backfill_multi_licensed_repositories"

class BackfillMultipleRepositoryLicenses < ActiveRecord::Migration[7.1]
  def self.up
    # Enterprise-only transition — temporarily reverted until at least GHES 3.8. The backfill was performed manually in production.
    return unless Rails.env.development?

    # Execute the transition
    trans = GitHub::Transitions::BackfillMultiLicensedRepositories.new(dry_run: false)
    trans.perform
  end

  def self.down
  end
end
