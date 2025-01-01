# typed: true
# frozen_string_literal: true

require "github/transitions/20230713181949_remove_old_grouped_board_views"

class RemoveOldGroupedBoardViewsTransition < ActiveRecord::Migration[7.1]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?
    transition = GitHub::Transitions::RemoveOldGroupedBoardViews.new(dry_run: false)
    transition.perform
  end

  def self.down
  end
end
