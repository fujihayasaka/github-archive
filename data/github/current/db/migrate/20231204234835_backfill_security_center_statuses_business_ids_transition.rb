# typed: true
# frozen_string_literal: true

require "github/transitions/20231204234835_backfill_security_center_statuses_business_ids"

class BackfillSecurityCenterStatusesBusinessIdsTransition < ActiveRecord::Migration[7.2]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?

    arguments = GitHub::Transitions::Arguments.new(dry_run: false)
    transition = GitHub::Transitions::BackfillSecurityCenterStatusesBusinessIds.new(arguments)
    transition.run
  end

  def self.down
  end
end
