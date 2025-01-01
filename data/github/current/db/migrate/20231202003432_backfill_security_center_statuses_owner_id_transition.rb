# typed: true
# frozen_string_literal: true

require "github/transitions/20231202003432_backfill_security_center_statuses_owner_id"

class BackfillSecurityCenterStatusesOwnerIdTransition < ActiveRecord::Migration[7.2]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?

    arguments = GitHub::Transitions::Arguments.new(dry_run: false)
    transition = GitHub::Transitions::BackfillSecurityCenterStatusesOwnerId.new(arguments)
    transition.run
  end

  def self.down
  end
end
