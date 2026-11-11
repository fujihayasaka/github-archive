# frozen_string_literal: true

class AddCheckrunIdToAutofixSuggestionJobs < ActiveRecord::Migration[7.0]
  def up
    change_table :autofix_suggestion_jobs, bulk: true do |t| # rubocop:disable Rails/NoBulkChangeTable
      t.bigint :check_run_id, unsigned: true
      t.change :id, :bigint, unsigned: true, null: false, auto_increment: true
    end
  end

  def down
    change_table :autofix_suggestion_jobs, bulk: true do |t| # rubocop:disable Rails/NoBulkChangeTable
      t.change :id, :bigint, unsigned: false, null: false, auto_increment: true
      t.remove :check_run_id
    end
  end
end
