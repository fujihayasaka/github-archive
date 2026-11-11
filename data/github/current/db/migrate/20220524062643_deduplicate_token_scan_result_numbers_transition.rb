# typed: true
# frozen_string_literal: true

require "github/transitions/20220510202221_deduplicate_token_scan_result_numbers"

class DeduplicateTokenScanResultNumbersTransition < ActiveRecord::Migration[7.0]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?
    transition = GitHub::Transitions::DeduplicateTokenScanResultNumbers.new(dry_run: false)
    transition.perform
  end

  def self.down
  end
end
