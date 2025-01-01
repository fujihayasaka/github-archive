# typed: true
# frozen_string_literal: true

require "github/transitions/20230720173335_backfill_memex_project_items_issues"

class BackfillMemexProjectItemsIssueData < ActiveRecord::Migration[7.1]
  def up
    return if !GitHub.enterprise? && !Rails.env.development?
    transition = GitHub::Transitions::BackfillMemexProjectItemsIssues.new(dry_run: false)
    transition.perform
  end

  def down
  end
end
