# typed: true
# frozen_string_literal: true

require "github/transitions/20230321155031_backfill_memex_column_values_for_enterprise_only"

class BackfillMemexColumnValuesForEnterpriseOnlyTransition < ActiveRecord::Migration[7.1]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?
    transition = GitHub::Transitions::BackfillMemexColumnValuesForEnterpriseOnly.new(dry_run: false)
    transition.perform
  end

  def self.down
  end
end
