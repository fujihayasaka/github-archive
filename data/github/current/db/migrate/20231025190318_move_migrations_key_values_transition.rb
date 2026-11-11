# typed: true
# frozen_string_literal: true

require "github/transitions/20231025190318_move_migrations_key_values"

class MoveMigrationsKeyValuesTransition < ActiveRecord::Migration[7.2]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?

    arguments = GitHub::Transitions::Arguments.new(dry_run: false)
    transition = GitHub::Transitions::MoveMigrationsKeyValues.new(arguments)
    transition.run
  end

  def self.down
  end
end
