# frozen_string_literal: true

class ConvertBigIntUnsignedColumnsToSigned < ActiveRecord::Migration[7.0]
  def up
    change_table :autofix_suggestion_jobs, bulk: true do |t| # rubocop:disable Rails/NoBulkChangeTable
      t.change :id, :bigint, unsigned: false
      t.change :check_run_id, :bigint, unsigned: false
    end

    change_table :suggested_fixes, bulk: true do |t| # rubocop:disable Rails/NoBulkChangeTable
      t.change :id, :bigint, unsigned: false
      t.change :autofix_suggestion_job_id, :bigint, unsigned: false
    end

    change_table :suggested_fix_files, bulk: true do |t| # rubocop:disable Rails/NoBulkChangeTable
      t.change :id, :bigint, unsigned: false
      t.change :suggested_fix_id, :bigint, unsigned: false
    end
  end

  def down
    change_table :autofix_suggestion_jobs, bulk: true do |t| # rubocop:disable Rails/NoBulkChangeTable
      t.change :id, :bigint, unsigned: true
      t.change :check_run_id, :bigint, unsigned: true
    end

    change_table :suggested_fixes, bulk: true do |t| # rubocop:disable Rails/NoBulkChangeTable
      t.change :id, :bigint, unsigned: true
      t.change :autofix_suggestion_job_id, :bigint, unsigned: true
    end

    change_table :suggested_fix_files, bulk: true do |t| # rubocop:disable Rails/NoBulkChangeTable
      t.change :id, :bigint, unsigned: true
      t.change :suggested_fix_id, :bigint, unsigned: true
    end
  end
end
