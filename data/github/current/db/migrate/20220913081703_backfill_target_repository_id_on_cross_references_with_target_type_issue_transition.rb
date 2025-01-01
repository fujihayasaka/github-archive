# typed: true
# frozen_string_literal: true

require "github/transitions/20220913081703_backfill_target_repository_id_on_cross_references_with_target_type_issue"

class BackfillTargetRepositoryIdOnCrossReferencesWithTargetTypeIssueTransition < ActiveRecord::Migration[7.0]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?
    transition = GitHub::Transitions::BackfillTargetRepositoryIdOnCrossReferencesWithTargetTypeIssue.new(dry_run: false)
    transition.perform
  end

  def self.down
  end
end
