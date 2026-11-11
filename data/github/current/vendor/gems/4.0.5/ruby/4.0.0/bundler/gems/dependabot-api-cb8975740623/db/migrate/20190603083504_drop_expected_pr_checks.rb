# frozen_string_literal: true

class DropExpectedPrChecks < ActiveRecord::Migration[6.0]
  def change
    remove_column :repos, :expected_pr_checks, :text
  end
end
