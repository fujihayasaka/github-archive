# typed: true
# frozen_string_literal: true

require "github/transitions/20230127014622_memex_add_due_date_to_milestone_column_values"

class MemexAddDueDateToMilestoneColumnValuesTransition < ActiveRecord::Migration[7.1]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?
    transition = GitHub::Transitions::MemexAddDueDateToMilestoneColumnValues.new(dry_run: false)
    transition.perform
  end

  def self.down
  end
end
