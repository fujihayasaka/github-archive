# typed: true
# frozen_string_literal: true

require "github/transitions/20240104131109_add_fgp_set_issue_type"

class AddFgpSetIssueTypeTransition < ActiveRecord::Migration[7.2]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?

    arguments = GitHub::Transitions::Arguments.new(dry_run: false)
    transition = GitHub::Transitions::AddFgpSetIssueType.new(arguments)
    transition.run
  end

  def self.down
  end
end
