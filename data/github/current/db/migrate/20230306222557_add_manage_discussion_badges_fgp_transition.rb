# typed: true
# frozen_string_literal: true

require "github/transitions/20230306214716_add_manage_discussion_badges_fgp"

class AddManageDiscussionBadgesFgpTransition < ActiveRecord::Migration[7.1]
  def self.up
    return if !GitHub.enterprise? && !GitHub::AppEnvironment.development?
    transition = GitHub::Transitions::AddManageDiscussionBadgesFgp.new(dry_run: false)
    transition.perform
  end

  def self.down
  end
end
