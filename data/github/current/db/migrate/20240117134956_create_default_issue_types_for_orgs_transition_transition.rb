# typed: true
# frozen_string_literal: true

require "github/transitions/20240117134956_create_default_issue_types_for_orgs_transition"

class CreateDefaultIssueTypesForOrgsTransitionTransition < ActiveRecord::Migration[7.2]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?

    arguments = GitHub::Transitions::Arguments.new(dry_run: false)
    transition = GitHub::Transitions::CreateDefaultIssueTypesForOrgsTransition.new(arguments)
    transition.run
  end

  def self.down
  end
end
