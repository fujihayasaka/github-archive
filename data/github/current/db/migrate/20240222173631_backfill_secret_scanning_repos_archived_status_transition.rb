# typed: true
# frozen_string_literal: true

require "github/transitions/20240222173631_backfill_secret_scanning_repos_archived_status"

class BackfillSecretScanningReposArchivedStatusTransition < ActiveRecord::Migration[7.2]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?

    arguments = GitHub::Transitions::Arguments.new(dry_run: false)
    transition = GitHub::Transitions::BackfillSecretScanningReposArchivedStatus.new(arguments)
    transition.run
  end

  def self.down
  end
end
