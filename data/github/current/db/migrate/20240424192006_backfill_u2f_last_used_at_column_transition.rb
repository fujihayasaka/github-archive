# typed: true
# frozen_string_literal: true

require "github/transitions/20240424192006_backfill_u2f_last_used_at_column"

class BackfillU2fLastUsedAtColumnTransition < ActiveRecord::Migration[7.2]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?

    arguments = GitHub::Transitions::Arguments.new(dry_run: false)
    transition = GitHub::Transitions::BackfillU2fLastUsedAtColumn.new(arguments)
    transition.run
  end

  def self.down
  end
end
