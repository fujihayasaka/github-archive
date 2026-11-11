# typed: true
# frozen_string_literal: true

require "github/transitions/20240408233756_backfill_sub_issues_memex_project_columns"

class BackfillSubIssuesMemexProjectColumnsTransition < ActiveRecord::Migration[7.2]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?

    arguments = GitHub::Transitions::Arguments.new(dry_run: false)
    transition = GitHub::Transitions::BackfillSubIssuesMemexProjectColumns.new(arguments)
    transition.run
  end

  def self.down
  end
end
