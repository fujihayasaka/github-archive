# typed: true
# frozen_string_literal: true

require "github/transitions/20230616194948_secret_scanning_repos_from_repositories_ghes_only"

class SecretScanningReposFromRepositoriesGhesOnlyTransition < ActiveRecord::Migration[7.1]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?
    transition = GitHub::Transitions::SecretScanningReposFromRepositoriesGhesOnly.new(dry_run: false)
    transition.perform
  end

  def self.down
  end
end
