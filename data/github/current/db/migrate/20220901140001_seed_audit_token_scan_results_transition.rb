# typed: true
# frozen_string_literal: true

require "github/transitions/20220901140001_seed_audit_token_scan_results"

class SeedAuditTokenScanResultsTransition < ActiveRecord::Migration[7.1]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?
    transition = GitHub::Transitions::SeedAuditTokenScanResults.new(dry_run: false)
    transition.perform
  end

  def self.down
  end
end
