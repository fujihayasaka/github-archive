# typed: true
# frozen_string_literal: true

require "github/transitions/20240715131550_default_issue_type_settings"

class DefaultIssueTypeSettingsTransition < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::IssuesPullRequests)

  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?

    arguments = GitHub::Transitions::Arguments.new(dry_run: false)
    transition = GitHub::Transitions::DefaultIssueTypeSettings.new(arguments)
    transition.run
  end

  def self.down
  end
end
