# typed: true
# frozen_string_literal: true

require "github/transitions/20240715231858_backfill_memex_project_last_visited_on_date"

class BackfillMemexProjectLastVisitedOnDateTransition < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::Memexes)

  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?

    arguments = GitHub::Transitions::Arguments.new(dry_run: false)
    transition = GitHub::Transitions::BackfillMemexProjectLastVisitedOnDate.new(arguments)
    transition.run
  end

  def self.down
  end
end
