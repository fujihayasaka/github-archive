# typed: true
# frozen_string_literal: true

require "github/transitions/20231115160949_cleanup_repositories_key_values"

class CleanupRepositoriesKeyValuesTransition < ActiveRecord::Migration[7.2]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?

    arguments = GitHub::Transitions::Arguments.new(dry_run: false)
    transition = GitHub::Transitions::CleanupRepositoriesKeyValues.new(arguments)
    transition.run
  end

  def self.down
  end
end
