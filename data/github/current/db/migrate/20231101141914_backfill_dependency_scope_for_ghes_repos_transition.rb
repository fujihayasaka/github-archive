# typed: true
# frozen_string_literal: true

require "github/transitions/20231101141914_backfill_dependency_scope_for_ghes_repos"

class BackfillDependencyScopeForGhesReposTransition < ActiveRecord::Migration[7.2]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?

    arguments = GitHub::Transitions::Arguments.new(dry_run: false)
    transition = GitHub::Transitions::BackfillDependencyScopeForGhesRepos.new(arguments)
    transition.run
  end

  def self.down
  end
end
