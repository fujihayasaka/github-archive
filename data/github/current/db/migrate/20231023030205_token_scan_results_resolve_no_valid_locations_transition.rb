# typed: true
# frozen_string_literal: true

require "github/transitions/20230817025712_token_scan_results_resolve_no_valid_locations"

class TokenScanResultsResolveNoValidLocationsTransition < ActiveRecord::Migration[7.2]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?

    arguments = GitHub::Transitions::Arguments.new(dry_run: false)
    transition = GitHub::Transitions::TokenScanResultsResolveNoValidLocations.new(dry_run: false)
    transition.run
  end

  def self.down
  end
end
