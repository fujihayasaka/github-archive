# typed: true
# frozen_string_literal: true

require "github/transitions/20231120222451_backfill_virtual_priority_on_memex_project_items"

class BackfillVirtualPriorityOnMemexProjectItemsTransition < ActiveRecord::Migration[7.2]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?

    arguments = GitHub::Transitions::Arguments.new(dry_run: false)
    transition = GitHub::Transitions::BackfillVirtualPriorityOnMemexProjectItemsOnMySQL5.new(arguments)
    transition.run
  end

  def self.down
  end
end
