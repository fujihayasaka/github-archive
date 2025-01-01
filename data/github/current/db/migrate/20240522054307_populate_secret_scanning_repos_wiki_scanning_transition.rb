# typed: true
# frozen_string_literal: true

require "github/transitions/20240522054307_populate_secret_scanning_repos_wiki_scanning"

class PopulateSecretScanningReposWikiScanningTransition < ActiveRecord::Migration[7.2]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?

    arguments = GitHub::Transitions::Arguments.new(dry_run: false)
    transition = GitHub::Transitions::PopulateSecretScanningReposWikiScanning.new(arguments)
    transition.run
  end

  def self.down
  end
end
