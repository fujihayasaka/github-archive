# frozen_string_literal: true

require "github/transitions/20230814181146_remove_orphaned_memex_template_rows"

class RemoveOrphanedMemexTemplateRowsTransition < ActiveRecord::Migration[7.1]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?
    transition = GitHub::Transitions::RemoveOrphanedMemexTemplateRows.new(dry_run: false)
    transition.perform
  end

  def self.down
  end
end
