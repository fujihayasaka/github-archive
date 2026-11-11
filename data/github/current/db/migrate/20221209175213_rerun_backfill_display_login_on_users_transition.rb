# typed: true
# frozen_string_literal: true

require "github/transitions/20221121143906_backfill_display_login_on_users"

class RerunBackfillDisplayLoginOnUsersTransition < ActiveRecord::Migration[7.1]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?
    transition = GitHub::Transitions::BackfillDisplayLoginOnUsers.new(dry_run: false)
    transition.perform
  end

  def self.down
  end
end
