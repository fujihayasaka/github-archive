# typed: true
# frozen_string_literal: true

require "github/transitions/20220901202644_add_bypass_id_to_token_scan_results"

class AddBypassIdToTokenScanResultsTransition < ActiveRecord::Migration[7.1]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?
    transition = GitHub::Transitions::AddBypassIdToTokenScanResults.new(dry_run: false)
    transition.perform
  end

  def self.down
  end
end
