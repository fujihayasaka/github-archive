# typed: true
# frozen_string_literal: true

require "github/transitions/20211103181137_backfill_token_scan_result_first_location"

class BackfillTokenScanResultFirstLocationTransition < ActiveRecord::Migration[7.1]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?
    transition = GitHub::Transitions::BackfillTokenScanResultFirstLocation.new(dry_run: false)
    transition.perform
  end

  def self.down
  end
end
