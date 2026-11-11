# typed: true
# frozen_string_literal: true

require "github/transitions/20230726134457_delete_duplicated_issues"

class DeleteDuplicatedIssuesTransition < ActiveRecord::Migration[7.1]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?
    transition = GitHub::Transitions::DeleteDuplicatedIssues.new(dry_run: false)
    transition.perform
  end

  def self.down
  end
end
