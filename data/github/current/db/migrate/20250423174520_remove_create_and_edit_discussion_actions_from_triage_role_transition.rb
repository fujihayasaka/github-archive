# typed: true
# frozen_string_literal: true

require "github/transitions/20250423174520_remove_create_and_edit_discussion_actions_from_triage_role"

# rubocop:disable GitHub/ConnectionClassPresentInMigration
# requiring a connection class is not necessary for transition migrations
class RemoveCreateAndEditDiscussionActionsFromTriageRoleTransition < ActiveRecord::Migration[8.1]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?

    arguments = GitHub::Transitions::Arguments.new(dry_run: false)
    transition = GitHub::Transitions::RemoveCreateAndEditDiscussionActionsFromTriageRole.new(arguments)
    transition.run
  end

  def self.down
  end
end
# rubocop:enable GitHub/ConnectionClassPresentInMigration
